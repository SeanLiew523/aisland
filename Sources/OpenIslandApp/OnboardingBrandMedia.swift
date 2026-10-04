import AppKit
import ImageIO

/// Compressed original-engine frames, decoded only as their 30Hz sample changes.
/// Full retina orbit predecode would retain roughly 400 MiB; the three current
/// frames and three reduced-motion stills bound the decoded cache instead.
@MainActor
final class OnboardingBrandMedia {
    struct Sequence: Decodable {
        let sampleStart: Double
        let sampleStep: Double
        let width: Int
        let height: Int
        let files: [String]
        let stillFile: String
        let stillTime: Double

        func frameIndex(sampleTime: Double) -> Int {
            // The prototype glyph cache uses the absolute scene tick, not time
            // since state entry. Thinking starts halfway through tick 238.
            let tick = Int(max(0, sampleTime) / sampleStep + 1e-9) - Int(sampleStart / sampleStep + 1e-9)
            return min(files.count - 1, max(0, tick))
        }
    }
    struct Manifest: Decodable {
        let revision: Int
        let fps: Double
        let sequences: [String: Sequence]
    }
    private struct Loaded {
        let metadata: Sequence
        let compressed: [Data]
        let still: CGImage
    }
    let manifest: Manifest
    private var sequences: [String: Loaded] = [:]
    private var current: [String: (index: Int, image: CGImage)] = [:]
    var decodedMotionFrameCount: Int { current.count }
    var compressedByteCount: Int { sequences.values.reduce(0) { $0 + $1.compressed.reduce(0) { $0 + $1.count } } }

    init(bundle: Bundle = .appResources) throws {
        func bytes(_ name: String) throws -> Data {
            let file = name as NSString
            guard let url = bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
            }
            return try Data(contentsOf: url)
        }
        manifest = try JSONDecoder().decode(Manifest.self, from: bytes("bloub-r9.json"))
        guard manifest.revision == 9, manifest.fps == 30,
              Set(manifest.sequences.keys) == Set(["idle", "thinking", "orbit"]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (state, sequence) in manifest.sequences {
            let expectedFrames = state == "idle" ? 80 : state == "thinking" ? 8 : 100
            let expectedSize = state == "orbit" ? 1024 : 256
            guard sequence.files.count == expectedFrames, Set(sequence.files).count == expectedFrames,
                  sequence.width == expectedSize, sequence.height == expectedSize,
                  sequence.sampleStep == 1 / manifest.fps,
                  sequence.sampleStart.isFinite, sequence.stillTime.isFinite else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let compressed = try sequence.files.map { try bytes($0) }
            // Validate compressed headers before the presentation starts, without
            // retaining every expanded retina texture. Decoder failure is surfaced
            // as media load failure rather than showing a partial welcome.
            for data in compressed {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      properties[kCGImagePropertyPixelWidth] as? Int == sequence.width,
                      properties[kCGImagePropertyPixelHeight] as? Int == sequence.height else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            guard let still = Self.decode(try bytes(sequence.stillFile)),
                  still.width == sequence.width, still.height == sequence.height else {
                throw CocoaError(.fileReadCorruptFile)
            }
            sequences[state] = Loaded(metadata: sequence, compressed: compressed, still: still)
        }
    }

    func image(state: String, sampleTime: Double, reduceMotion: Bool) -> CGImage? {
        guard let sequence = sequences[state], sampleTime.isFinite else { return nil }
        if reduceMotion { return sequence.still }
        let index = sequence.metadata.frameIndex(sampleTime: sampleTime)
        if let cached = current[state], cached.index == index { return cached.image }
        guard let image = Self.decode(sequence.compressed[index]) else { return nil }
        current[state] = (index, image)
        return image
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
