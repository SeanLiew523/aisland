import Testing
import AVFoundation
@testable import OpenIslandCore

struct NotificationSoundStoreTests {
    private func environment(_ body: (NotificationSoundStore, UserDefaults, URL) throws -> Void) throws {
        let suite = "NotificationSoundTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try body(NotificationSoundStore(defaults: defaults, directory: root.appendingPathComponent("managed")), defaults, root)
    }

    private func source(_ root: URL, name: String = "chime.mp3") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(base64Encoded: Self.mp3)!.write(to: url)
        return url
    }

    @Test
    func testLegacyMigrationIsIndependentAndDoesNotOverwriteOnRestart() throws {
        try environment { _, defaults, root in
            defaults.set("Glass", forKey: "notification.sound.name")
            for category in NotificationSoundCategory.allCases {
                defaults.removeObject(forKey: "notification.sound.category." + category.rawValue)
            }
            let store = NotificationSoundStore(defaults: defaults, directory: root.appendingPathComponent("managed"))
            for category in NotificationSoundCategory.allCases { #expect(store.selection(for: category) == .system(name: "Glass")) }
            store.selectSystem("Ping", for: .approval)
            let restarted = NotificationSoundStore(defaults: defaults, directory: store.directory)
            #expect(restarted.selection(for: .completed) == .system(name: "Glass"))
            #expect(restarted.selection(for: .approval) == .system(name: "Ping"))
            #expect(restarted.selection(for: .answer) == .system(name: "Glass"))
            #expect(defaults.string(forKey: "notification.sound.name") == "Glass")
        }
    }

    @Test
    func testThreeImportsAreIndependentAndManagedCopiesSurviveSourceMoveAndRestart() throws {
        try environment { store, defaults, root in
            let original = try source(root)
            var assets: [NotificationSoundCategory: ManagedNotificationSound] = [:]
            for category in NotificationSoundCategory.allCases { assets[category] = try store.importMP3(from: original, for: category) }
            try FileManager.default.moveItem(at: original, to: root.appendingPathComponent("moved.mp3"))
            let restarted = NotificationSoundStore(defaults: defaults, directory: store.directory)
            for category in NotificationSoundCategory.allCases {
                #expect(restarted.selection(for: category) == .custom(assets[category]!))
                #expect(!(restarted.resolve(category).usedFallback))
                #expect(restarted.resolve(category).fileURL != original)
                #expect(assets[category]!.duration > 0)
            }
            #expect(Set(assets.values.map(\.filename)).count == 3)
        }
    }

    @Test
    func testInvalidAndOversizedImportsKeepPriorAssetAndLeaveNoStagingFiles() throws {
        try environment { store, _, root in
            let asset = try store.importMP3(from: source(root), for: .answer)
            let bad = root.appendingPathComponent("broken.mp3")
            try Data("not audio".utf8).write(to: bad)
            #expect(throws: (any Error).self) { try store.importMP3(from: bad, for: .answer) }
            let huge = root.appendingPathComponent("huge.mp3")
            FileManager.default.createFile(atPath: huge.path, contents: nil)
            let handle = try FileHandle(forWritingTo: huge)
            try handle.truncate(atOffset: UInt64(NotificationSoundStore.maximumImportBytes + 1))
            try handle.close()
            #expect(throws: (any Error).self) { try store.importMP3(from: huge, for: .answer) }
            #expect(store.selection(for: .answer) == .custom(asset))
            #expect(!(store.resolve(.answer).usedFallback))
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == [asset.filename])
        }
    }

    @Test
    func testFailedStagingValidationAndUnreadableSourceKeepPreviousSelection() throws {
        try environment { store, defaults, root in
            let original = try source(root)
            let asset = try store.importMP3(from: original, for: .completed)
            let failing = NotificationSoundStore(defaults: defaults, directory: store.directory, validate: { _ in
                throw NotificationSoundImportError.invalidAudio
            })
            #expect(throws: (any Error).self) { try failing.importMP3(from: original, for: .completed) }
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: original.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path) }
            #expect(throws: (any Error).self) { try store.importMP3(from: original, for: .completed) }
            #expect(store.selection(for: .completed) == .custom(asset))
            #expect(!(store.resolve(.completed).usedFallback))
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == [asset.filename])
        }
    }

    @Test
    func testAtomicRenameFailureKeepsPriorAsset() throws {
        try environment { store, defaults, root in
            let original = try source(root)
            let asset = try store.importMP3(from: original, for: .completed)
            let failing = NotificationSoundStore(defaults: defaults, directory: store.directory, validate: { staged in
                try FileManager.default.removeItem(at: staged)
                return 1
            })
            #expect(throws: (any Error).self) { try failing.importMP3(from: original, for: .completed) }
            #expect(store.selection(for: .completed) == .custom(asset))
            #expect(!(store.resolve(.completed).usedFallback))
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == [asset.filename])
        }
    }

    @Test
    func testResetDoesNotRemoveAnotherCategoryReferenceWithDifferentMetadata() throws {
        try environment { store, defaults, root in
            let asset = try store.importMP3(from: source(root), for: .completed)
            let shared = ManagedNotificationSound(filename: asset.filename, displayName: "other", duration: 2)
            defaults.set(try JSONEncoder().encode(NotificationSoundSelection.custom(shared)), forKey: "notification.sound.category.answer")
            store.restoreDefault(for: .completed)
            #expect(!(store.resolve(.answer).usedFallback))
            store.restoreDefault(for: .answer)
            #expect(!(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(asset.filename).path)))
        }
    }

    @Test
    func testRenamedWAVIsRejectedEvenThoughItCanDecode() throws {
        try environment { store, _, root in
            let wav = root.appendingPathComponent("renamed.mp3")
            // Minimal valid PCM WAV; container bytes, rather than the extension, decide acceptance.
            var data = Data("RIFF".utf8)
            func u32(_ x: UInt32) { var le = x.littleEndian; data.append(Data(bytes: &le, count: 4)) }
            func u16(_ x: UInt16) { var le = x.littleEndian; data.append(Data(bytes: &le, count: 2)) }
            u32(36 + 200); data.append(Data("WAVEfmt ".utf8)); u32(16)
            u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16)
            data.append(Data("data".utf8)); u32(200); data.append(Data(repeating: 0, count: 200))
            try data.write(to: wav)
            #expect(throws: (any Error).self) { try store.importMP3(from: wav, for: .approval) }
            #expect(store.selection(for: .approval) == .system(name: "Bottle"))
        }
    }

    @Test
    func testMissingAndCorruptManagedFilesFallbackWithSelectedMetadataRetained() throws {
        try environment { store, _, root in
            let original = try source(root)
            let asset = try store.importMP3(from: original, for: .completed)
            let managed = store.resolve(.completed).fileURL!
            try Data("corrupt".utf8).write(to: managed)
            #expect(store.resolve(.completed).usedFallback)
            #expect(store.resolve(.completed).selection == .system(name: "Bottle"))
            #expect(store.selection(for: .completed) == .custom(asset))
            try FileManager.default.removeItem(at: managed)
            #expect(store.resolve(.completed).usedFallback)
            #expect(store.resolve(.completed).fileURL == nil)
        }
    }

    @Test
    func testReplacementAndResetCleanOnlyTheirOwnManagedFiles() throws {
        try environment { store, _, root in
            let original = try source(root)
            let first = try store.importMP3(from: original, for: .completed)
            let other = try store.importMP3(from: original, for: .approval)
            let replacement = try store.importMP3(from: original, for: .completed)
            #expect(!(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(first.filename).path)))
            #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(other.filename).path))
            store.restoreDefault(for: .completed)
            #expect(!(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(replacement.filename).path)))
            #expect(FileManager.default.fileExists(atPath: original.path))
            #expect(!(store.resolve(.approval).usedFallback))
        }
    }

    @Test
    func testUntrustedMetadataAndSymlinksCannotDeleteOutsideManagedDirectory() throws {
        try environment { store, defaults, root in
            let original = try source(root)
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let filename = UUID().uuidString + ".mp3"
            let linked = store.directory.appendingPathComponent(filename)
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: original)
            let asset = ManagedNotificationSound(filename: filename, displayName: "fake", duration: 1)
            defaults.set(try JSONEncoder().encode(NotificationSoundSelection.custom(asset)), forKey: "notification.sound.category.answer")
            #expect(store.resolve(.answer).usedFallback)
            store.restoreDefault(for: .answer)
            #expect(FileManager.default.fileExists(atPath: original.path))
            #expect(FileManager.default.fileExists(atPath: linked.path))
            let escaping = ManagedNotificationSound(filename: "../" + filename, displayName: "escape", duration: 1)
            defaults.set(try JSONEncoder().encode(NotificationSoundSelection.custom(escaping)), forKey: "notification.sound.category.answer")
            #expect(store.resolve(.answer).usedFallback)
            store.restoreDefault(for: .answer)
            #expect(FileManager.default.fileExists(atPath: original.path))
        }
    }

    @Test
    func testSymlinkedManagedDirectoryRejectsImportsAndPlaybackModeRestores() throws {
        try environment { store, defaults, root in
            let original = try source(root)
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: store.directory, withDestinationURL: outside)
            #expect(throws: (any Error).self) { try store.importMP3(from: original, for: .completed) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
            #expect(store.playbackMode == .shortFade)
            store.playbackMode = .full
            #expect(NotificationSoundStore(defaults: defaults, directory: store.directory).playbackMode == .full)
        }
    }

    // Original synthetic sine, generated with libmp3lame; no user audio or external fixture.
    private static let mp3 = "//NAxAAUOHKEH1gIAFJJJaI3G43G43G43G6eMQw7DkO5DlVgZd8zEMgC4imjuRikpLAwfB8Hz8EAQ4Pv5yjz/KO0B/gR2gP8CO4f6Pf0fwfAgIAgCAYB8H3wICHf0EFwAIIIMIGBAAD/80LEChcxHqGXmpgCPszr//0vmU/V9kaqoCKwUDJjgGPDAB1FwjmgHnIkwB8k4s4UEKC/IaOaOaUv8ixFjEul3/ykRYixiXSZMv5YKgqIgr/wVEQVBURHjv/5URBUNFqIAADzCDT/3///80DECRTIei4130gAaCfuUafgsAHDgAMAQDUwGAAbEIFiYIsMeGhjC55hp4PIYRmBFGAlgDhgEwCaYBwAMhgAiFwAJEa/YVM7/s/9v/q/d//////+23bVlAAAFsbELkGa+Wpa+rdlHf/zQsQQEpByOl4PuCxF4qAGjIFxgEBOmE6p8biaYZjBdnXzUZUEZh8DAoGobMFfqiuAtudV3Zqz+j+v7X/+7//V0/93v1bqFYAABE7/efqJuBDbXCyZiQgZSTmlJBw8KYIsCPGG5jP5tf/zQMQhEyB6Igjf+oAWNtHogXmcCUGA44jAYEgJkoBKytEfeXya+5d3///Yjoft3/+7//X//+7+pQBIkhG0///91nIdhY4JAHQBGAUA4YIALBgWAkmGSJ2ZQcbps7NUGSeKSYwAKhgq//NCxC8UmHYwfV4YAAPgkEwNABiEAVLN+KQIhPRex6l+v/f/Z6Uav7f/0f/3eqttagQ8VXAJEQZgVhsNhcLQAAP+HUv05XU+CkRzVRNOpHHaU99UDxF7gRgVXAtqzcWaREpcLpg23FvA//NAxDgiUjM/H5mQk9tCaABt4gmTxOFsMDADEHJhZ74swdguQiCxUwxqTwhKN7+OAplczJ83IuKRFwjWICUBzjL/uzoMg1Ac4myBFshqRRKpR//renT381OIwsg5L2p0lAlBmXS7J9n/80LECROAxiQB2GAAL5B6EK3LqiamLBVFjK45wTNCojOQt9A7DXFbkmMPodASCo+hWrVv7WclkxMXmVq06VDYlBUsDQwOxEHBEHfiU6JXUf4iTEFNRTQuMKqqqqqqqqqqqqqqqqqqqqo="
}

@MainActor
private final class TestSoundPlayer: NotificationSoundPlayer {
    let duration: TimeInterval
    var volume: Float = 1 { didSet { volumes.append(volume) } }
    var volumes: [Float] = []
    var failureHandler: (@MainActor () -> Void)?
    var plays = 0
    var stops = 0
    var succeeds = true
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    init(duration: TimeInterval) { self.duration = duration }
    func play() -> Bool { plays += 1; return succeeds }
    func stop() {
        stops += 1
        let waiters = stopWaiters; stopWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    func waitForStop() async {
        guard stops == 0 else { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }
}

/// Logical time only. Requests and stop callbacks provide explicit scheduling
/// handshakes, so no assertion depends on how fast the shared MainActor runs.
@MainActor
private final class TestSoundClock {
    private(set) var now: TimeInterval = 0
    private var sleepers: [UUID: (TimeInterval, CheckedContinuation<Void, any Error>)] = [:]
    private var requests: [TimeInterval] = []
    private var requestWaiters: [CheckedContinuation<TimeInterval, Never>] = []

    func playback() -> NotificationSoundPlayback {
        NotificationSoundPlayback(now: { self.now }, sleepUntil: { try await self.sleep(until: $0) })
    }

    func nextSleep() async -> TimeInterval {
        if !requests.isEmpty { return requests.removeFirst() }
        return await withCheckedContinuation { requestWaiters.append($0) }
    }

    func advance(to time: TimeInterval) {
        precondition(time >= now)
        now = time
        let due = sleepers.filter { $0.value.0 <= time }
        for (id, sleeper) in due {
            sleepers.removeValue(forKey: id)
            sleeper.1.resume()
        }
    }

    private func sleep(until deadline: TimeInterval) async throws {
        try Task.checkCancellation()
        if requestWaiters.isEmpty { requests.append(deadline) }
        else { requestWaiters.removeFirst().resume(returning: deadline) }
        guard deadline > now else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { sleepers[id] = (deadline, continuation) }
            }
        } onCancel: {
            Task { @MainActor in
                self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }
}

struct NotificationSoundPlaybackTests {
    @MainActor
    @Test
    func testReplacementCancelsOldTimerAndMuteReleasesCurrentPlayer() async throws {
        let clock = TestSoundClock(), owner = clock.playback()
        let first = TestSoundPlayer(duration: 3)
        let second = TestSoundPlayer(duration: 10)
        #expect(owner.play(first))
        #expect(await clock.nextSleep() == 3)
        #expect(owner.play(second))
        #expect(await clock.nextSleep() == 10)
        #expect(first.stops == 1)
        clock.advance(to: 4)
        #expect(owner.isPlaying)
        #expect(second.stops == 0)
        owner.setMuted(true)
        #expect(!(owner.isPlaying))
        #expect(second.stops == 1)
        let muted = TestSoundPlayer(duration: 10)
        #expect(!(owner.play(muted, isMuted: true)))
        #expect(muted.plays == 0)
        // Wake canceled timers after global mute; they must not change either player.
        clock.advance(to: 20)
        #expect(first.stops == 1 && second.stops == 1)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testAutomaticLimitFadesAndReleasesWhilePreviewPlaysFullDuration() async throws {
        let clock = TestSoundClock(), owner = clock.playback()
        let automatic = TestSoundPlayer(duration: 20)
        #expect(owner.play(automatic, limit: 6, fadeDuration: 3))
        #expect(await clock.nextSleep() == 3)
        clock.advance(to: 3)
        for step in 1...10 {
            let deadline = 3 + 3 * Double(step) / 10
            #expect(await clock.nextSleep() == deadline)
            // The next sleep is registered only after the preceding volume update.
            #expect(automatic.volume == Float(11 - step) / 10)
            clock.advance(to: deadline)
        }
        await automatic.waitForStop()
        #expect(!(owner.isPlaying))
        #expect(automatic.stops == 1)
        #expect(automatic.volumes.contains(where: { $0 > 0 && $0 < 1 }))
        #expect(automatic.volume == 0)
        let preview = TestSoundPlayer(duration: 30)
        #expect(owner.play(preview))
        #expect(await clock.nextSleep() == 36)
        clock.advance(to: 35)
        #expect(owner.isPlaying)
        #expect(preview.volume == 1)
        clock.advance(to: 36)
        await preview.waitForStop()
        #expect(!(owner.isPlaying))
        #expect(preview.stops == 1)
    }

    @MainActor
    @Test
    func testStopAndFailedPlayLeaveNoRetainedPlayback() {
        let owner = NotificationSoundPlayback()
        weak var retained: TestSoundPlayer?
        do {
            let player = TestSoundPlayer(duration: 1)
            retained = player
            owner.play(player)
            owner.stop()
        }
        #expect(retained == nil)
        let failed = TestSoundPlayer(duration: 1)
        failed.succeeds = false
        #expect(!(owner.play(failed)))
        #expect(!(owner.isPlaying))
        #expect(failed.stops == 1)
    }

    @MainActor
    @Test
    func testMutedAutomaticEventLeavesManualPreviewUntilGlobalMuteChanges() {
        let owner = NotificationSoundPlayback()
        let preview = TestSoundPlayer(duration: 1)
        let suppressed = TestSoundPlayer(duration: 1)
        var fallbackAttempts = 0
        #expect(owner.play(preview))
        #expect(!owner.play(suppressed, isMuted: true, fallback: { fallbackAttempts += 1; return nil }))
        #expect(owner.isPlaying)
        #expect(preview.stops == 0)
        #expect(suppressed.plays == 0)
        #expect(suppressed.stops == 0)
        #expect(fallbackAttempts == 0)
        owner.setMuted(true)
        #expect(!owner.isPlaying)
        #expect(preview.stops == 1)
    }

    @MainActor
    @Test
    func testStartFailureUsesExactlyOneFallbackAndFallbackFailureStops() {
        let owner = NotificationSoundPlayback()
        let failed = TestSoundPlayer(duration: 1)
        failed.succeeds = false
        let replacement = TestSoundPlayer(duration: 1)
        var attempts = 0
        #expect(owner.play(failed, fallback: { attempts += 1; return replacement }))
        #expect(failed.stops == 1)
        #expect(failed.failureHandler == nil)
        #expect(replacement.plays == 1)
        #expect(attempts == 1)
        owner.stop()
        replacement.succeeds = false
        #expect(!owner.play(failed, fallback: { attempts += 1; return replacement }))
        #expect(!owner.isPlaying)
        #expect(attempts == 2)
        #expect(replacement.plays == 2)
        #expect(replacement.failureHandler == nil)
    }

    @MainActor
    @Test
    func testDecodeFailureFallsBackOnceAndRejectsStaleCallbacks() {
        let owner = NotificationSoundPlayback()
        let decoded = TestSoundPlayer(duration: 1)
        let replacement = TestSoundPlayer(duration: 1)
        var attempts = 0
        owner.play(decoded, fallback: { attempts += 1; return replacement })
        let oldCallback = decoded.failureHandler
        oldCallback?()
        #expect(attempts == 1)
        #expect(decoded.stops == 1)
        #expect(replacement.plays == 1)
        oldCallback?()
        #expect(attempts == 1)
        #expect(replacement.stops == 0)
        // A failure in the fallback terminates playback rather than retrying again.
        replacement.failureHandler?()
        #expect(!owner.isPlaying)
        #expect(attempts == 1)
        #expect(replacement.stops == 1)
        let newest = TestSoundPlayer(duration: 1)
        owner.play(newest)
        oldCallback?()
        #expect(newest.stops == 0)
        #expect(attempts == 1)
        owner.stop()
    }

    @MainActor
    @Test
    func testQueuedFailureAfterStopOrReplacementCannotStartFallback() {
        let owner = NotificationSoundPlayback()
        let original = TestSoundPlayer(duration: 1)
        var attempts = 0
        owner.play(original, fallback: { attempts += 1; return TestSoundPlayer(duration: 1) })
        let stale = original.failureHandler
        owner.setMuted(true)
        stale?()
        #expect(!owner.isPlaying)
        #expect(attempts == 0)
        owner.play(original, fallback: { attempts += 1; return TestSoundPlayer(duration: 1) })
        let beforeReplacement = original.failureHandler
        let current = TestSoundPlayer(duration: 1)
        owner.play(current)
        beforeReplacement?()
        #expect(attempts == 0)
        #expect(current.stops == 0)
        owner.stop()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testRuntimeFallbackKeepsAutomaticDeadlineInsteadOfRestartingLimit() async throws {
        let clock = TestSoundClock(), owner = clock.playback()
        let original = TestSoundPlayer(duration: 10)
        let replacement = TestSoundPlayer(duration: 10)
        #expect(owner.play(original, limit: 4, fadeDuration: 0, fallback: { replacement }))
        #expect(await clock.nextSleep() == 4)
        clock.advance(to: 2)
        original.failureHandler?()
        #expect(replacement.plays == 1)
        #expect(await clock.nextSleep() == 4)
        clock.advance(to: 4)
        await replacement.waitForStop()
        #expect(!owner.isPlaying)
        #expect(replacement.stops == 1)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testPreviewStartFailureStillPlaysFullFallback() async throws {
        let clock = TestSoundClock(), owner = clock.playback()
        let original = TestSoundPlayer(duration: 10)
        original.succeeds = false
        let replacement = TestSoundPlayer(duration: 3)
        #expect(owner.play(original, fallback: { replacement }))
        #expect(await clock.nextSleep() == 3)
        clock.advance(to: 2)
        #expect(owner.isPlaying)
        #expect(replacement.volume == 1)
        clock.advance(to: 3)
        await replacement.waitForStop()
        #expect(!owner.isPlaying)
        #expect(replacement.stops == 1)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testShortAutomaticAudioEndsNaturallyWithoutFadeAtNonzeroClockOrigin() async {
        let clock = TestSoundClock(), owner = clock.playback()
        clock.advance(to: 1000)
        let player = TestSoundPlayer(duration: 0.3)
        #expect(owner.play(player, limit: 5))
        #expect(await clock.nextSleep() == 1000.3)
        clock.advance(to: 1000.3)
        await player.waitForStop()
        #expect(player.volumes == [1] && player.stops == 1)
        #expect(!owner.isPlaying)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testDelayedTimerStartupDoesNotExtendAutomaticDeadline() async {
        let clock = TestSoundClock(), owner = clock.playback()
        let player = TestSoundPlayer(duration: 20)
        #expect(owner.play(player, limit: 6, fadeDuration: 3))
        // No scheduling yield: model a MainActor occupied past the deadline.
        clock.advance(to: 10)
        await player.waitForStop()
        #expect(!owner.isPlaying)
        #expect(player.stops == 1 && player.volume == 0)
        #expect(await clock.nextSleep() == 3)
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func testLateFadeContinuationUsesOriginalStepAndEndInstants() async {
        let clock = TestSoundClock(), owner = clock.playback()
        let player = TestSoundPlayer(duration: 20)
        #expect(owner.play(player, limit: 6, fadeDuration: 3))
        #expect(await clock.nextSleep() == 3)
        // Resume the fade well past its first few steps. It must not add a new fade budget.
        clock.advance(to: 6)
        await player.waitForStop()
        #expect(player.stops == 1 && player.volume == 0)
        #expect(!owner.isPlaying)
        #expect(await clock.nextSleep() == 3.3)
    }

    @MainActor
    @Test
    func testRuntimeFailureAfterAutomaticDeadlineCannotStartFallback() {
        let clock = TestSoundClock(), owner = clock.playback()
        let original = TestSoundPlayer(duration: 20)
        let replacement = TestSoundPlayer(duration: 20)
        #expect(owner.play(original, limit: 4, fallback: { replacement }))
        clock.advance(to: 5)
        original.failureHandler?()
        #expect(original.stops == 1)
        #expect(replacement.plays == 0 && replacement.stops == 1)
        #expect(!owner.isPlaying)
    }
}
