import AppKit

/// Clipboard bytes stay in memory. Restore only if no subsequent producer
/// changed the pasteboard; never overwrite a new user copy during navigation.
struct MiniMaxCodePasteboardSnapshot {
    let originalChangeCount: Int
    private let items: [NSPasteboardItem]
    static func capture(_ pasteboard: NSPasteboard) -> Self? {
        let count = pasteboard.changeCount
        let originals = pasteboard.pasteboardItems ?? []
        guard originals.count <= 16 else { return nil }
        var copies: [NSPasteboardItem] = []; var total = 0
        for original in originals {
            guard original.types.count <= 16 else { return nil }
            let item = NSPasteboardItem()
            for type in original.types {
                guard let data = original.data(forType: type) else { return nil }
                total += data.count
                guard total <= 1_048_576, item.setData(data, forType: type) else { return nil }
            }
            copies.append(item)
        }
        guard pasteboard.changeCount == count else { return nil }
        return Self(originalChangeCount: count, items: copies)
    }
    struct CopyResult {
        let sessionID: String
        let restored: Bool
    }
    /// A changed board is not automatically our copy. Restore only a stable,
    /// bounded value equal to the exact admitted session ID; preserve all other
    /// producers, including a user's copy between click and first observation.
    func consumeMatchingCopy(_ pasteboard: NSPasteboard, expectedID: String) -> CopyResult? {
        let producedCount = pasteboard.changeCount
        guard producedCount != originalChangeCount,
              let data = pasteboard.data(forType: .string), data.count <= 512,
              pasteboard.changeCount == producedCount,
              let value = String(data: data, encoding: .utf8), value == expectedID else { return nil }
        return CopyResult(sessionID: value, restored: restore(pasteboard, ifUnchangedSince: producedCount))
    }
    @discardableResult func restore(_ pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        return items.isEmpty || pasteboard.writeObjects(items)
    }
}
