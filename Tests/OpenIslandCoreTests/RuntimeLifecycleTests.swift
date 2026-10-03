import Foundation
import Darwin
import Testing
@testable import OpenIslandCore

struct RuntimeLifecycleTests {
    private func payload(_ event: RuntimeLifecycleHookPayload.Event, turn: String = "t1", time: Double = 1,
                         source: RuntimeLifecycleHookPayload.Source = .hermesCLI, profile: String = "default",
                         session: String = "s1", sequence: Int? = nil) -> RuntimeLifecycleHookPayload {
        RuntimeLifecycleHookPayload(source: source, event: event, profileID: profile, sessionID: session,
            turnID: turn, sequence: sequence, cwd: "/tmp/project", timestamp: Date(timeIntervalSince1970: time))
    }
    private func succeeds(_ events: [AgentEvent]) -> Bool {
        events.contains { if case let .sessionCompleted(value) = $0 { return value.isInterrupt != true }; return false }
    }
    @Test func successFailureAndInterrupt() {
        for end in [RuntimeLifecycleHookPayload.Event.turnCompleted, .turnFailed, .turnInterrupted, .sessionEnded] {
            var reducer = RuntimeLifecycleReducer()
            let start = reducer.receive(payload(.turnStarted))
            #expect(start.count == 1)
            let result = reducer.receive(payload(end, time: 2))
            #expect(succeeds(result) == (end == .turnCompleted))
            #expect(reducer.receive(payload(end, time: 3)).isEmpty)
        }
    }
    @Test func disposalAfterCompletedTurnEndsSessionWithoutAnotherSuccess() {
        var reducer = RuntimeLifecycleReducer()
        _ = reducer.receive(payload(.turnStarted))
        _ = reducer.receive(payload(.turnCompleted, time: 2))
        let disposal = reducer.receive(payload(.sessionEnded, time: 3))
        #expect(!succeeds(disposal))
        var state = SessionState()
        for event in reducer.receive(payload(.turnStarted, turn: "t2", time: 4)) { state.apply(event) }
        for event in reducer.receive(payload(.turnFailed, turn: "t2", time: 5)) { state.apply(event) }
        #expect(state.sessions.first?.runtimeOutcome == .failed)
        #expect(reducer.receive(payload(.turnCompleted, turn: "t2", time: 6)).isEmpty)
    }

    @Test func lateTurnCannotEndOrReopenCurrentTurn() {
        var reducer = RuntimeLifecycleReducer()
        _ = reducer.receive(payload(.turnStarted))
        _ = reducer.receive(payload(.turnStarted, turn: "t2", time: 2))
        #expect(reducer.receive(payload(.turnCompleted, time: 3)).isEmpty)
        #expect(reducer.receive(payload(.turnStarted, time: 4)).isEmpty)
        #expect(succeeds(reducer.receive(payload(.turnCompleted, turn: "t2", time: 5))))
    }
    @Test func restoredAndUnobservedCompletionNeverNotify() throws {
        let registry = FileManager.default.temporaryDirectory.appendingPathComponent("runtime-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: registry) }
        var first = RuntimeLifecycleReducer(registryURL: registry)
        _ = first.receive(payload(.turnStarted))
        var restored = RuntimeLifecycleReducer(registryURL: registry)
        var restoredState = SessionState()
        for event in restored.restoredEvents { restoredState.apply(event) }
        #expect(restoredState.sessions.first?.phase == .running)
        #expect(!succeeds(restored.restoredEvents))
        #expect(restored.receive(payload(.turnStarted, time: 2)).isEmpty)
        #expect(!succeeds(restored.receive(payload(.turnCompleted, time: 3))))
        var unknown = RuntimeLifecycleReducer()
        #expect(!succeeds(unknown.receive(payload(.turnCompleted))))
        #expect(unknown.receive(payload(.turnStarted, time: 2)).isEmpty)
    }
    @Test func sourceProfileAndSessionRemainIndependent() {
        var reducer = RuntimeLifecycleReducer()
        for source in [RuntimeLifecycleHookPayload.Source.hermesCLI, .deepseekHarness] {
            for profile in ["default", "other"] {
                _ = reducer.receive(payload(.turnStarted, source: source, profile: profile))
            }
        }
        for source in [RuntimeLifecycleHookPayload.Source.hermesCLI, .deepseekHarness] {
            for profile in ["default", "other"] {
                #expect(succeeds(reducer.receive(payload(.turnCompleted, time: 2, source: source, profile: profile))))
            }
        }
    }
    @Test func pluginReloadCompletionSettlesMatchingTurnSilently() {
        var reducer = RuntimeLifecycleReducer()
        _ = reducer.receive(payload(.turnStarted, source: .deepseekHarness))
        var end = payload(.turnCompleted, time: 2, source: .deepseekHarness)
        end.sourceObservedStart = false
        let events = reducer.receive(end)
        #expect(!succeeds(events))
        #expect(events.contains { if case let .sessionCompleted(value) = $0 { return value.runtimeOutcome == .succeeded }; return false })
    }

    @Test func staleSequenceAndTimestampAreIgnored() {
        var reducer = RuntimeLifecycleReducer()
        _ = reducer.receive(payload(.turnStarted, time: 3, sequence: 10))
        #expect(reducer.receive(payload(.turnCompleted, time: 4, sequence: 9)).isEmpty)
        #expect(reducer.receive(payload(.turnCompleted, time: 2, sequence: 11)).isEmpty)
        #expect(succeeds(reducer.receive(payload(.turnCompleted, time: 4, sequence: 11))))
    }
    @Test func deepSeekFixedReasonProjectionIsAccepted() {
        for reason in ["completed", "error", "blocked", "max-tokens", "aborted:user", "aborted:parent", "aborted:hook", "aborted:disposed", "aborted:legacy", "aborted:unknown", "interrupted", "forked", "unknown"] {
            var value = payload(.turnCompleted, source: .deepseekHarness)
            value.resultReason = reason
            #expect(value.isValid)
        }
    }

    @Test func identityControlsLengthsAndReasonBoundaries() {
        var value = payload(.turnStarted)
        value.sessionID = "s\nother"; #expect(!value.isValid)
        value.sessionID = String(repeating: "a", count: 513); #expect(!value.isValid)
        value.sessionID = "s"; value.resultReason = "private diagnostic"; #expect(!value.isValid)
        value.resultReason = "text_response"; #expect(value.isValid)
    }

    @Test func bridgeDeliversNativeLifecycleMetadataForBothSources() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socketURL) }
        let observer = socket(AF_UNIX, SOCK_STREAM, 0)
        guard observer >= 0 else { throw BridgeTransportError.notConnected }
        defer { close(observer) }
        try disableSocketSigPipe(observer)
        try withUnixSocketAddress(path: socketURL.path) { address, length in
            guard Darwin.connect(observer, address, length) == 0 else { throw BridgeTransportError.notConnected }
        }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        #expect(setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0)
        try writeAll(try BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: observer)
        var buffer = Data()
        func readEnvelopes() throws -> [BridgeEnvelope] {
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = read(observer, &bytes, bytes.count)
            guard count > 0 else { throw BridgeTransportError.responseTimedOut }
            buffer.append(contentsOf: bytes.prefix(count))
            return try BridgeCodec.decodeLines(from: &buffer)
        }
        var registered = false
        while !registered { registered = try readEnvelopes().contains(.response(.acknowledged)) }
        let client = BridgeCommandClient(socketURL: socketURL)
        for source in [RuntimeLifecycleHookPayload.Source.hermesCLI, .deepseekHarness] {
            #expect(try client.send(.processRuntimeLifecycleHook(payload(.turnStarted, source: source)), timeout: 1) == .acknowledged)
            #expect(try client.send(.processRuntimeLifecycleHook(payload(.turnCompleted, time: 2, source: source)), timeout: 1) == .acknowledged)
        }
        var events: [AgentEvent] = []
        while events.filter({ if case .sessionCompleted = $0 { return true }; return false }).count < 2 {
            events += try readEnvelopes().compactMap { if case let .event(event) = $0 { return event }; return nil }
        }
        var state = SessionState()
        for event in events { state.apply(event) }
        #expect(Set(state.sessions.map(\.tool)) == [.hermesCLI, .deepseekHarness])
        #expect(state.sessions.allSatisfy { $0.runtimeOutcome == .succeeded && $0.phase == .completed })
    }

    @Test func wireUsesMillisecondsAndMetadataOnly() throws {
        let value = payload(.turnStarted, source: .deepseekHarness)
        let data = try BridgeCodec.encodeLine(.command(.processRuntimeLifecycleHook(value)))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let command = try #require(json["command"] as? [String: Any])
        let hook = try #require(command["runtimeLifecycleHook"] as? [String: Any])
        #expect(command["type"] as? String == "processRuntimeLifecycleHook")
        #expect(hook["timestamp"] as? Double == 1000)
        #expect(hook["profile_id"] as? String == "default")
        var buffer = data
        #expect(try BridgeCodec.decodeLines(from: &buffer) == [.command(.processRuntimeLifecycleHook(value))])
    }
}
