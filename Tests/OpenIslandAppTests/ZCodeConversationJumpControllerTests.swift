import Foundation
import SQLite3
import Testing
@testable import OpenIslandApp

struct ZCodeConversationJumpControllerTests {
    @Test
    func selectedSidebarWithoutExactCurrentIDCannotVerifyNavigation() {
        #expect(!ZCodeSidebarContract.verifiesIdentity(
            rowCount: 1, selectedRowCount: 1, copiedID: nil, targetID: "sess_exact"))
        #expect(!ZCodeSidebarContract.verifiesIdentity(
            rowCount: 2, selectedRowCount: 1, copiedID: "sess_exact", targetID: "sess_exact"))
        #expect(!ZCodeSidebarContract.verifiesIdentity(
            rowCount: 1, selectedRowCount: 0, copiedID: "sess_exact", targetID: "sess_exact"))
        #expect(ZCodeSidebarContract.verifiesIdentity(
            rowCount: 1, selectedRowCount: 1, copiedID: "sess_exact", targetID: "sess_exact"))
    }

    @Test
    func failedNavigationMetadataNeverRetainsTitlesURLsOrRawSessionIDs() {
        let target = "sess_private-fixture"
        let row = ZCodeNavigationDiagnostic.Element(
            attributeNames: ["AXRole", "AXDOMIdentifier", "not an attribute\nprivate"],
            identityValues: ["AXDOMIdentifier": target, "AXURL": "file:///private/workspace",
                             "AXValue": "Private conversation text", "data-session-id": target],
            targetID: target)
        let diagnostic = ZCodeNavigationDiagnostic(
            targetHash: ZCodeNavigationDiagnostic.hash(target), rowCount: 1,
            selectedRowCount: 1, headingMatches: false, row: row, content: nil)
        #expect(row.attributeNames == ["AXDOMIdentifier", "AXRole"])
        #expect(row.identityMatches["AXDOMIdentifier"] == true)
        #expect(row.identityMatches["AXURL"] == false)
        #expect(row.identityHashes.count == 2)
        #expect(!diagnostic.line.contains(target))
        #expect(!diagnostic.line.contains("/private/workspace"))
        #expect(!diagnostic.line.contains("Private conversation text"))
        #expect(!diagnostic.line.contains("data-session-id"))
        #expect(diagnostic.line.contains("content=[missing]"))
    }

    @Test
    func oversizedIdentityMetadataIsDiscarded() {
        let metadata = ZCodeNavigationDiagnostic.Element(
            attributeNames: [], identityValues: ["AXURL": String(repeating: "x", count: 4_097)],
            targetID: "sess_fixture")
        #expect(metadata.identityHashes.isEmpty)
    }

    @Test
    func taskIndexResolvesConversationTitleAndWorkspaceByHookSessionID() throws {
        let fixture = try makeTaskIndex()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let record = fixture.taskIndex.conversation(id: "sess_exact")

        #expect(
            record == ZCodeConversationRecord(
                id: "sess_exact",
                title: "Watch配对与新增Agent支持",
                workspacePath: "/Users/demo/open-vibe-island"
            )
        )
        #expect(fixture.taskIndex.hasUniqueTitle(for: try #require(record)))
        #expect(fixture.taskIndex.conversation(id: "missing") == nil)
    }

    @Test
    func duplicateTitleInAnotherWorkspaceDisablesStandaloneLookup() throws {
        let fixture = try makeTaskIndex(extraSQL: """
        INSERT INTO tasks VALUES ('sess_other', 'Watch配对与新增Agent支持', '/Users/demo/other', 43, 0);
        """)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let record = try #require(fixture.taskIndex.conversation(id: "sess_exact"))

        #expect(!fixture.taskIndex.hasUniqueTitle(for: record))
    }

    @Test
    func duplicateTitleInSameWorkspaceDisablesStandaloneLookup() throws {
        let fixture = try makeTaskIndex(extraSQL: """
        INSERT INTO tasks VALUES ('sess_other', ' Watch配对与新增Agent支持 ', '/Users/demo/open-vibe-island', 43, 0);
        """)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let record = try #require(fixture.taskIndex.conversation(id: "sess_exact"))

        #expect(!fixture.taskIndex.hasUniqueTitle(for: record))
    }

    @Test
    func deletedDuplicateDoesNotBlockAnExistingStandaloneTask() throws {
        let fixture = try makeTaskIndex(extraSQL: """
        INSERT INTO tasks VALUES ('sess_deleted', 'Watch配对与新增Agent支持', '/Users/demo/other', 43, 1);
        """)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let record = try #require(fixture.taskIndex.conversation(id: "sess_exact"))

        #expect(fixture.taskIndex.hasUniqueTitle(for: record))
        #expect(!fixture.taskIndex.hasUniqueTitle(for: ZCodeConversationRecord(
            id: "missing", title: record.title, workspacePath: record.workspacePath
        )))
    }

    @Test
    func expiredFocusDeadlineStopsBeforeAccessibilityOrAppActivation() throws {
        let fixture = try makeTaskIndex()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let controller = ZCodeConversationJumpController(
            taskIndex: fixture.taskIndex,
            clock: { 0 },
            focusTimeout: 0
        )

        #expect(controller.focus(conversationID: "sess_exact") == .unavailable("focus-timeout"))
    }

    private func makeTaskIndex(extraSQL: String = "") throws -> (rootURL: URL, taskIndex: ZCodeTaskIndex) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-zcode-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let databaseURL = rootURL.appendingPathComponent("tasks-index.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let openedDatabase = try #require(database)
        defer { sqlite3_close(openedDatabase) }

        let schema = """
        CREATE TABLE tasks (
            task_id TEXT NOT NULL,
            title TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO tasks (task_id, title, workspace_path, updated_at, deleted)
        VALUES (
            'sess_exact',
            'Watch配对与新增Agent支持',
            '/Users/demo/open-vibe-island',
            42,
            0
        );
        """
        #expect(sqlite3_exec(openedDatabase, schema + extraSQL, nil, nil, nil) == SQLITE_OK)

        return (rootURL, ZCodeTaskIndex(databasePath: databaseURL.path))
    }
}
