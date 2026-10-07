import Foundation
import CryptoKit
let package = URL(fileURLWithPath: CommandLine.arguments[1])
guard let raw = Data(base64Encoded: CommandLine.arguments[2]), raw.count == 32 else { fatalError("Invalid public key") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
let feed = try Data(contentsOf: package.appendingPathComponent("appcast.xml"))
let text = String(decoding: feed, as: UTF8.self)
func captures(_ pattern: String, _ text: String) throws -> [String] {
    let regex = try NSRegularExpression(pattern: pattern)
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    guard matches.count == 1, let match = matches.first else { fatalError("Missing or ambiguous signature") }
    return (1..<match.numberOfRanges).map { String(text[Range(match.range(at: $0), in: text)!]) }
}
let pattern = #"<!-- sparkle-signatures:\s*edSignature:\s*([A-Za-z0-9+/=]+)\s*length:\s*([0-9]+)\s*-->\s*$"#
let metadata = try captures(pattern, text)
guard let length = Int(metadata[1]), length > 0, length < feed.count,
      let signature = Data(base64Encoded: metadata[0]), signature.count == 64,
      key.isValidSignature(signature, for: feed.prefix(length)) else { fatalError("Feed signature invalid") }
let signedText = String(decoding: feed.prefix(length), as: UTF8.self)
let suffix = String(decoding: feed.dropFirst(length), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
guard try captures("^" + pattern, suffix) == metadata else { fatalError("Unsigned feed contents") }
let attributes = try captures(#"sparkle:edSignature="([A-Za-z0-9+/=]+)"\s+length="([0-9]+)""#, signedText)
let archive = try Data(contentsOf: package.appendingPathComponent("AIsland.zip"))
guard UInt64(attributes[1]) == UInt64(archive.count), let archiveSignature = Data(base64Encoded: attributes[0]),
      key.isValidSignature(archiveSignature, for: archive) else { fatalError("Archive signature invalid") }
print("Verified archive and appcast Ed25519 signatures using the public key only.")
