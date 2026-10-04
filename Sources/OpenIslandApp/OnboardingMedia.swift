import AppKit
import ImageIO
import OpenIslandCore

@MainActor
final class OnboardingMedia {
    struct Clip: Decodable {
        struct Page: Decodable { let file: String; let offset: Int; let frames: Int }
        let fps: Double
        let columns: Int
        let pages: [Page]
        let frames: Int
        let width: Int
        let height: Int
    }
    struct Manifest: Decodable { let clips: [String: [String: Clip]] }
    struct Frames { let metadata: Clip; let frames: [CGImage]; let still: CGImage }
    let clips: [String: Frames]
    let logos: [CGImage]
    let rows: [CGImage]
    let brand: OnboardingBrandMedia

    init(language: OnboardingLanguage, bundle: Bundle = .appResources) throws {
        func url(_ name: String) throws -> URL {
            let file = name as NSString
            guard let result = bundle.url(forResource: file.deletingPathExtension,
                                          withExtension: file.pathExtension) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
            }
            return result
        }
        func image(_ name: String) throws -> CGImage {
            let source = CGImageSourceCreateWithURL(try url(name) as CFURL, nil)
            guard let source, let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: name])
            }
            return image
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url("native-media.json")))
        guard let metadata = manifest.clips[language.rawValue] else { throw CocoaError(.fileReadCorruptFile) }
        var clips: [String: Frames] = [:]
        for (key, clip) in metadata {
            var frames: [CGImage] = []
            for page in clip.pages {
                let atlas = try image(page.file)
                guard page.offset == frames.count else { throw CocoaError(.fileReadCorruptFile) }
                for i in 0..<page.frames {
                    let rect = CGRect(x: (i % clip.columns) * clip.width, y: (i / clip.columns) * clip.height,
                                      width: clip.width, height: clip.height)
                    guard let crop = atlas.cropping(to: rect),
                          let context = CGContext(data: nil, width: clip.width, height: clip.height,
                                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    // Decode each cropped frame before starting the score; retain
                    // small textures rather than uploading atlases at transitions.
                    context.draw(crop, in: CGRect(x: 0, y: 0, width: clip.width, height: clip.height))
                    guard let decoded = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
                    frames.append(decoded)
                }
            }
            guard frames.count == clip.frames else { throw CocoaError(.fileReadCorruptFile) }
            clips[key] = Frames(metadata: clip, frames: frames, still: try image("native-\(key)-\(language.rawValue)-still.png"))
        }
        self.clips = clips
        self.logos = try ["claude", "chatgpt", "gemini", "grok", "kimi", "minimax", "zcode", "deepseek", "workbuddy"].map { try image("\($0).png") }
        self.rows = try ["claude", "codex", "gemini", "workbuddy"].map {
            try image("native-row-\($0)-\(language == .chinese ? "zh-Hans" : "en")@2x.png")
        }
        self.brand = try OnboardingBrandMedia(bundle: bundle)
    }
}
