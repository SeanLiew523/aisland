import Foundation
import Testing

/// Sticky fixture completion: background callbacks signal directly, and waiting
/// tests suspend without polling the main actor or counting scheduler backlog.
final class StartupFixtureSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    func signal() {
        let pending = lock.withLock {
            completed = true
            let pending = Array(waiters.values)
            waiters.removeAll()
            return pending
        }
        for continuation in pending { continuation.resume() }
    }

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let immediate: Result<Void, any Error>? = lock.withLock {
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if completed { return .success(()) }
                    waiters[id] = continuation
                    return nil
                }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            let pending = self.lock.withLock { self.waiters.removeValue(forKey: id) }
            pending?.resume(throwing: CancellationError())
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct StartupFixtureSignalTests {
    @Test func completionBroadcastsAndRemainsReadyForLateWaiters() async throws {
        let signal = StartupFixtureSignal()
        let first = Task { try await signal.wait() }
        let second = Task { try await signal.wait() }
        signal.signal(); signal.signal()
        try await first.value; try await second.value
        try await signal.wait()
    }

    @Test func cancellationUnblocksWithoutACompletionSignal() async {
        let signal = StartupFixtureSignal()
        let waiter = Task { try await signal.wait() }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
    }
}
