// Export the production BloubLayerView at media resolution, without changing its
// paths, animation configuration, colors, or timing. Source is compiled separately
// from the pinned app commit by extract-status.py.
import AppKit
import QuartzCore

@main
enum StatusCapture {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 408, height: 408),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.level = .floating
        window.isReleasedWhenClosed = false
        let states: [(String, UnifiedBars.Mode, BloubTint, Int)] = [
            ("idle", .idle, .paper, 240), ("thinking", .running, .paper, 30),
            ("approval", .waiting, .approval, 500), ("answer", .waiting, .answer, 500)
        ]
        var views: [BloubLayerView] = []
        for (index, state) in states.enumerated() {
            let origin = NSPoint(x: 8 + (index % 2) * 200, y: 8 + (index / 2) * 200)
            let view = BloubLayerView(frame: NSRect(origin: origin, size: NSSize(width: 192, height: 192)))
            view.update(mode: state.1, isActive: true, reduceMotion: false,
                        tint: state.2, waitingMotion: .alive, backdrop: .black)
            window.contentView!.addSubview(view)
            views.append(view)
            try! FileManager.default.createDirectory(at: output.appendingPathComponent(state.0),
                                                      withIntermediateDirectories: true)
        }
        window.orderFrontRegardless()
        window.contentView!.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            precondition(views.allSatisfy { $0.hasScheduledAnimations }, "Native animations are not active")
            var frame = 0
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                for (index, state) in states.enumerated() where frame < state.3 {
                    let view = views[index]
                    let context = CGContext(data: nil, width: 384, height: 384, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.setFillColor(NSColor.black.cgColor)
                    context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
                    context.translateBy(x: 0, y: 384)
                    context.scaleBy(x: 2, y: -2)
                    view.layer!.presentation()!.render(in: context)
                    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
                    let url = output.appendingPathComponent(state.0)
                        .appendingPathComponent(String(format: "frame-%04d.png", frame))
                    try! image.representation(using: .png, properties: [:])!.write(to: url)
                }
                frame += 1
                if frame == 500 {
                    timer.invalidate()
                    views.forEach { $0.tearDown() }
                    window.close()
                    app.terminate(nil)
                }
            }
        }
        app.run()
    }
}
