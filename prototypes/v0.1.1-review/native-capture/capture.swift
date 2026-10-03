// Appended to the extracted production row in the same compilation unit.
// Private component visibility and all native drawing code remain unchanged.
import AppKit

@MainActor
func captureRows() throws {
    guard CommandLine.arguments.count == 3, ["zh-Hans", "en"].contains(CommandLine.arguments[2]) else {
        throw NSError(domain: "NativeRows", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected output directory and language (zh-Hans or en)"])
    }
    let language = CommandLine.arguments[2]
    let chinese = language == "zh-Hans"
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let now = Date()
    let examples: [(AgentTool, String, String)] = [
        (.claudeCode, "claude", chinese ? "示例项目 · 整理页面设计稿" : "Demo project · Organize page designs"),
        (.codex, "codex", chinese ? "示例项目 · 检查代码修改" : "Demo project · Review code changes"),
        (.geminiCLI, "gemini", chinese ? "示例项目 · 汇总调研资料" : "Demo project · Summarize research"),
        (.workbuddy, "workbuddy", chinese ? "示例项目 · 准备会议摘要" : "Demo project · Prepare meeting notes"),
    ]
    var records: [[String: Any]] = []
    for (tool, slug, title) in examples {
        let session = AgentSession(id: "native-row-demo-\(slug)", title: title,
                                   tool: tool, origin: .demo, attachmentState: .detached,
                                   phase: .running, summary: chinese ? "静态原生组件示例" : "Static native component example", updatedAt: now,
                                   jumpTarget: nil, codexMetadata: nil, claudeMetadata: nil,
                                   geminiMetadata: nil, openCodeMetadata: nil, cursorMetadata: nil,
                                   piMetadata: nil)
        let row = IslandSessionRow(session: session, referenceDate: now,
                                   stateIndicator: .glyph, isActionable: false,
                                   useDrawingGroup: false, isInteractive: false,
                                   onApprove: nil, onAnswer: nil, onReply: nil,
                                   onJump: {}, onDismiss: nil)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: language))
        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 360, height: nil)
        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "NativeRows", code: 2, userInfo: [NSLocalizedDescriptionKey: "ImageRenderer failed for \(slug)"])
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "NativeRows", code: 3)
        }
        let file = "native-row-\(slug)-\(language)@2x.png"
        try png.write(to: output.appendingPathComponent(file), options: .atomic)
        records.append(["file": file, "agent": tool.rawValue, "title": title, "language": language,
                        "summary": session.summary,
                        "origin": "demo", "phase": "running", "scale": 2,
                        "pixelWidth": cgImage.width, "pixelHeight": cgImage.height,
                        "pointWidth": Double(cgImage.width) / 2,
                        "pointHeight": Double(cgImage.height) / 2,
                        "metadata": NSNull(), "jumpTarget": NSNull(), "isInteractive": false,
                        "onApprove": NSNull(), "onAnswer": NSNull(), "onReply": NSNull(),
                        "onDismiss": NSNull(), "onJump": "noop", "stateIndicator": "glyph"])
        print("Exported \(file): \(cgImage.width)×\(cgImage.height)")
    }
    let manifest: [String: Any] = ["renderer": "SwiftUI.ImageRenderer", "nativeComponent": "IslandSessionRow",
                                  "realSessionData": false, "windowCreated": false, "language": language,
                                  "capturedAt": ISO8601DateFormatter().string(from: now), "rows": records]
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent("native-row-manifest-\(language).json"), options: .atomic)
}

do {
    try MainActor.assumeIsolated { try captureRows() }
} catch {
    fputs("Native row capture failed: \(error)\n", stderr)
    exit(1)
}
