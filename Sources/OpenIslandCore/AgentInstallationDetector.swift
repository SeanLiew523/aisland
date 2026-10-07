import Foundation

/// Installation evidence only. Never examines agent config, sessions or credentials,
/// and never executes a source program. Inject roots to keep tests away from user data.
public struct AgentInstallationDetector: Sendable {
    public struct Evidence: Equatable, Sendable {
        public var executableURL: URL
        public var bundleURL: URL?
        public var version: String?
    }
    public var executableDirectories: [URL]
    public var applicationDirectories: [URL]

    public init(executableDirectories: [URL]? = nil, applicationDirectories: [URL]? = nil,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.executableDirectories = executableDirectories ?? Array(Set(
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                .map(String.init).filter { $0.hasPrefix("/") }
            + ["/opt/homebrew/bin", "/usr/local/bin", home.path + "/.local/bin", home.path + "/.bun/bin", home.path + "/.npm-global/bin"]
        )).sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.applicationDirectories = applicationDirectories ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    public func detect() -> [AgentIdentifier: Evidence] {
        var result: [AgentIdentifier: Evidence] = [:]
        for (agent, names) in Self.commands {
            if let executable = executableDirectories.lazy.flatMap({ directory in names.map { directory.appendingPathComponent($0) } }).first(where: Self.isExecutable) {
                result[agent] = Evidence(executableURL: executable.resolvingSymlinksInPath(), bundleURL: nil, version: nil)
            }
        }
        for (agent, name, identity) in Self.applications {
            for directory in applicationDirectories {
                let app = directory.appendingPathComponent(name, isDirectory: true)
                let infoURL = app.appendingPathComponent("Contents/Info.plist")
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: infoURL.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 65_536,
                      let data = try? Data(contentsOf: infoURL), data.count <= 65_536,
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      info["CFBundleIdentifier"] as? String == identity,
                      let executableName = info["CFBundleExecutable"] as? String,
                      !executableName.isEmpty, !executableName.contains("/"), executableName != ".", executableName != ".." else { continue }
                let executable = app.appendingPathComponent("Contents/MacOS/" + executableName)
                guard Self.isExecutable(executable) else { continue }
                result[agent] = Evidence(executableURL: executable, bundleURL: app,
                    version: info["CFBundleShortVersionString"] as? String)
                break
            }
        }
        return result
    }

    private static func isExecutable(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            && FileManager.default.isExecutableFile(atPath: resolved.path)
    }
    private static let commands: [AgentIdentifier: [String]] = [
        .claudeCode: ["claude"], .codex: ["codex"], .qoder: ["qoder"], .qwenCode: ["qwen"],
        .factory: ["droid"], .codebuddy: ["codebuddy"], .zcode: ["zcode"], .workbuddy: ["workbuddy"],
        .openCode: ["opencode"], .cursor: ["cursor"], .gemini: ["gemini"], .kimi: ["kimi"],
        .grok: ["grok"], .pi: ["pi"], .ohMyPi: ["omp"], .hermes: ["hermes"],
    ] // mcode deliberately deferred; Claude usage is optional rather than task-event setup.
    private static let applications: [(AgentIdentifier, String, String)] = [
        (.cursor, "Cursor.app", "com.todesktop.230313mzl4w4u92"),
        (.qoder, "Qoder.app", "com.qoder.app"), (.qoder, "Qoder.app", "com.qoder.qoder"),
        (.zcode, "ZCode.app", "dev.zcode.app"), (.workbuddy, "WorkBuddy.app", "com.tencent.workbuddy.mac"),
        (.deepSeekDesktop, "DeepSeek Harness.app", "com.deepseek.dsh"),
        (.miniMaxCodeDesktop, "MiniMax Code.app", "com.minimax.agent"),
    ]
}
