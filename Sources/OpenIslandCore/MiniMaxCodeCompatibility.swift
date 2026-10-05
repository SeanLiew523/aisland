/// Explicitly reviewed Desktop versions sharing the native metadata and UI
/// contracts. A patch version is never admitted by a numeric range.
public enum MiniMaxCodeCompatibility {
    public static let desktopVersions: Set<String> = ["3.1.0", "3.1.1"]
    public static func supportsDesktop(_ version: String?) -> Bool {
        version.map(desktopVersions.contains) ?? false
    }
}
