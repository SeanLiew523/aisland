import Foundation
import Testing
@testable import OpenIslandApp

private actor MonitoringStartupPause {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false
    func wait() async {
        isWaiting = true
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { isOpen = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class MonitoringStartupTrace {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

@MainActor private func waitForMonitoringStartup(_ predicate: @MainActor () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(await predicate())
}

@MainActor struct StartupLiveMonitoringTests {
    @Test func normalMonitoringStartsOnceWhileHistoryAndSetupArePaused() async throws {
        let workflows = StartupWorkflows(), trace = MonitoringStartupTrace()
        let history = MonitoringStartupPause(), setup = MonitoringStartupPause()
        defer { Task { await history.release(); await setup.release() } }
        workflows.start(history: {
            await history.wait()
            await trace.record("history")
        }, connections: {
            await setup.wait()
            trace.record("setup")
        })
        try await waitForMonitoringStartup {
            let historyWaiting = await history.isWaiting
            let setupWaiting = await setup.isWaiting
            return historyWaiting && setupWaiting
        }

        workflows.startLiveMonitoringIfNeeded(loadRuntimeState: true, isRuntimeAcceptance: false,
            bridgeStarted: true) { trace.record("monitoring") }
        workflows.startLiveMonitoringIfNeeded(loadRuntimeState: true, isRuntimeAcceptance: false,
            bridgeStarted: true) { trace.record("duplicate-monitoring") }
        #expect(trace.events == ["monitoring"])
        await history.release()
        await setup.release()
        try await waitForMonitoringStartup { trace.events.count == 3 }
        workflows.startLiveMonitoringIfNeeded(loadRuntimeState: true, isRuntimeAcceptance: false,
            bridgeStarted: true) { trace.record("late-duplicate-monitoring") }
        #expect(Set(trace.events) == ["monitoring", "history", "setup"])
    }

    @Test(arguments: ["runtimeAcceptance", "sourceSetupAcceptance", "deterministicHarness", "bridgeDisabled", "bridgeFailed"])
    func isolatedOrUnavailableStartupRegistersNoOrdinaryMonitor(_ mode: String) {
        let workflows = StartupWorkflows()
        var starts = 0
        let acceptance = mode == "runtimeAcceptance" || mode == "sourceSetupAcceptance"
        let loadRuntimeState = mode != "deterministicHarness"
        let bridgeStarted = mode != "bridgeDisabled" && mode != "bridgeFailed"
        for _ in 0..<2 {
            workflows.startLiveMonitoringIfNeeded(loadRuntimeState: loadRuntimeState,
                isRuntimeAcceptance: acceptance, bridgeStarted: bridgeStarted) { starts += 1 }
        }
        #expect(starts == 0)
    }

    @Test func successfulBridgeRetryCanStartMonitoringExactlyOnce() {
        let workflows = StartupWorkflows()
        var starts = 0
        workflows.startLiveMonitoringIfNeeded(loadRuntimeState: true, isRuntimeAcceptance: false,
            bridgeStarted: false) { starts += 1 }
        #expect(starts == 0)
        for _ in 0..<2 {
            workflows.startLiveMonitoringIfNeeded(loadRuntimeState: true, isRuntimeAcceptance: false,
                bridgeStarted: true) { starts += 1 }
        }
        #expect(starts == 1)
    }
}
