import AppKit
import Testing
@testable import OpenIslandApp

struct MiniMaxCodePasteboardSnapshotTests {
    private func withBoard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let board = NSPasteboard(name: .init("aisland-test-copy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("original-user-copy", forType: .string)
        try body(board)
    }
    @Test func targetCopyIsConsumedAndOriginalIsRestored() throws {
        try withBoard { board in
            let snapshot = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
            board.clearContents(); board.setString("mvs_target", forType: .string)
            let result = try #require(snapshot.consumeMatchingCopy(board, expectedID: "mvs_target"))
            #expect(result.sessionID == "mvs_target")
            #expect(result.restored)
            #expect(board.string(forType: .string) == "original-user-copy")
        }
    }
    @Test func userCopyAfterDeliveryIsPreserved() throws {
        try withBoard { board in
            let snapshot = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
            board.clearContents(); board.setString("new-user-copy", forType: .string)
            let count = board.changeCount
            #expect(snapshot.consumeMatchingCopy(board, expectedID: "mvs_target") == nil)
            #expect(board.changeCount == count)
            #expect(board.string(forType: .string) == "new-user-copy")
        }
    }
    @Test func unchangedAndOversizedValuesAreNotRestored() throws {
        try withBoard { board in
            let snapshot = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
            #expect(snapshot.consumeMatchingCopy(board, expectedID: "original-user-copy") == nil)
            board.clearContents(); board.setString(String(repeating: "x", count: 513), forType: .string)
            let count = board.changeCount
            #expect(snapshot.consumeMatchingCopy(board, expectedID: "mvs_target") == nil)
            #expect(board.changeCount == count)
        }
    }
    @Test func newerProducerIsNotOverwrittenByRestoration() throws {
        try withBoard { board in
            let snapshot = try #require(MiniMaxCodePasteboardSnapshot.capture(board))
            board.clearContents(); board.setString("mvs_target", forType: .string)
            let producedCount = board.changeCount
            board.clearContents(); board.setString("later-user-copy", forType: .string)
            #expect(!snapshot.restore(board, ifUnchangedSince: producedCount))
            #expect(board.string(forType: .string) == "later-user-copy")
        }
    }
}
