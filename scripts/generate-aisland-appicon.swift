#!/usr/bin/env swift
// Native production rendering of the selected C1 concept, using the original
// 160×64 flat-top notch silhouette. No generated bitmap is resized or retouched.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets/Brand/AIsland", isDirectory: true)
let iconset = root.appendingPathComponent("AIsland.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    let paper = CGColor(red: 0xf1 / 255, green: 0xea / 255, blue: 0xd9 / 255, alpha: 1)
    let ink = CGColor(red: 0x0d / 255, green: 0x0d / 255, blue: 0x0f / 255, alpha: 1)
    let blue = CGColor(red: 0x36 / 255, green: 0x74 / 255, blue: 0xf5 / 255, alpha: 1)
    // Match the project's native macOS content grid, leaving transparent margins.
    let content = size * 824 / 1024
    let inset = (size - content) / 2
    context.translateBy(x: inset, y: inset)
    context.scaleBy(x: content / 1024, y: content / 1024)
    context.setFillColor(paper)
    context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                          cornerWidth: 230.4, cornerHeight: 230.4, transform: nil))
    context.fillPath()

    let width: CGFloat = 1024 * 0.72
    context.translateBy(x: (1024 - width) / 2, y: (1024 - width * 64 / 160) / 2)
    context.scaleBy(x: width / 160, y: width / 160)
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: 0, y: 64))
    notch.addLine(to: CGPoint(x: 160, y: 64))
    notch.addLine(to: CGPoint(x: 160, y: 32))
    notch.addArc(center: CGPoint(x: 128, y: 32), radius: 32, startAngle: 0,
                 endAngle: -.pi / 2, clockwise: true)
    notch.addLine(to: CGPoint(x: 32, y: 0))
    notch.addArc(center: CGPoint(x: 32, y: 32), radius: 32, startAngle: -.pi / 2,
                 endAngle: .pi, clockwise: true)
    notch.closeSubpath()
    context.setFillColor(ink)
    context.addPath(notch)
    context.fillPath()
    context.setFillColor(paper)
    for x: CGFloat in [47, 65] {
        context.saveGState()
        context.translateBy(x: x, y: 32)
        context.rotate(by: 8 * .pi / 180)
        context.addPath(CGPath(roundedRect: CGRect(x: -4.3, y: -9.2, width: 8.6, height: 18.4),
                              cornerWidth: 4.3, cornerHeight: 4.3, transform: nil))
        context.fillPath()
        context.restoreGState()
    }
    context.setFillColor(blue)
    context.fillEllipse(in: CGRect(x: 110, y: 26, width: 12, height: 12))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(base * scale).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
try render(1024).write(to: root.appendingPathComponent("app-icon.png"))
print("Rendered C1 AIsland icon at all native macOS sizes.")
