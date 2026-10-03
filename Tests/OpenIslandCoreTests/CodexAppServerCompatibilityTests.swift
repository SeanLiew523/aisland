import Foundation
import Testing
@testable import OpenIslandCore

struct CodexAppServerCompatibilityTests {
    private let threadJSON = #"{"id":"desktop","cwd":"/tmp/project","preview":"Working","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"status":{"type":"idle"},"source":{"subAgent":{"other":"review"}}}"#

    @Test
    func modernLoadedListContainsIDsRatherThanThreadObjects() throws {
        let result = try JSONDecoder().decode(CodexLoadedThreadListResult.self, from: Data(#"{"data":["desktop"],"nextCursor":"page-2"}"#.utf8))
        #expect(result.ids == ["desktop"])
        #expect(result.legacyThreads.isEmpty)
        #expect(result.nextCursor == "page-2")
    }

    @Test(arguments: ["data", "threads"])
    func allThreadListSupportsModernAndLegacyObjects(key: String) throws {
        let result = try JSONDecoder().decode(CodexThreadListResult.self, from: Data("{\"\(key)\":[\(threadJSON)]}".utf8))
        #expect(result.threads.map(\.id) == ["desktop"])
        #expect(result.threads.first?.source == .unknown)
    }

    @Test
    func legacyLoadedListStillDecodesThreadObjects() throws {
        let result = try JSONDecoder().decode(CodexLoadedThreadListResult.self, from: Data("{\"threads\":[\(threadJSON)]}".utf8))
        #expect(result.legacyThreads.map(\.id) == ["desktop"])
        #expect(result.ids.isEmpty)
    }

    @Test
    func malformedListIsNotReportedAsAnEmptySuccess() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CodexLoadedThreadListResult.self, from: Data("{}".utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CodexThreadListResult.self, from: Data("{}".utf8))
        }
    }

    @Test
    func loadedIDsAreHydratedWithMetadataOnlyReads() async throws {
        let client = CodexAppServerClient()
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting
        client.requestTimeoutSeconds = 2
        let recorder = RPCRecorder()
        let thread = threadJSON
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = request["id"] as? Int,
                  let method = request["method"] as? String else { return }
            recorder.append(method: method, metadataOnly: (request["params"] as? [String: Any])?["includeTurns"] as? Bool == false)
            let result = method == "thread/loaded/list" ? #"{"data":["desktop"],"nextCursor":null}"# : "{\"thread\":\(thread)}"
            client.handleIncomingData(Data("{\"id\":\(id),\"result\":\(result)}\n".utf8))
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            client.stop()
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        let threads = try await client.listLoadedThreads()
        #expect(threads.map(\.id) == ["desktop"])
        #expect(recorder.methods == ["thread/loaded/list", "thread/read"])
        #expect(recorder.didReadMetadataOnly)
    }

    @Test
    func executableResolverSupportsNestedAndLegacyLayoutsWithoutDependingOnAppName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Renamed Desktop.app")
        let nested = bundle.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents")
        try FileManager.default.createDirectory(at: nested.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleExecutable": "codex", "CFBundleIdentifier": "com.openai.codex.cli", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: nested.appendingPathComponent("Info.plist"))
        let modern = nested.appendingPathComponent("MacOS/codex")
        let legacy = bundle.appendingPathComponent("Contents/Resources/codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: modern)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: legacy)
        for url in [modern, legacy] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        #expect(CodexAppServerExecutable.resolve(in: bundle) == modern)
        try FileManager.default.removeItem(at: modern)
        #expect(CodexAppServerExecutable.resolve(in: bundle) == legacy)
        try FileManager.default.removeItem(at: legacy)
        #expect(CodexAppServerExecutable.resolve(in: bundle) == nil)
    }
}

private final class RPCRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, Bool)] = []
    func append(method: String, metadataOnly: Bool) { lock.withLock { entries.append((method, metadataOnly)) } }
    var methods: [String] { lock.withLock { entries.map(\.0) } }
    var didReadMetadataOnly: Bool { lock.withLock { entries.contains { $0.0 == "thread/read" && $0.1 } } }
}
