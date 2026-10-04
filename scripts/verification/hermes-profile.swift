import Foundation

/// Compile this probe with the actual HermesHookInstallationManager.swift.
/// A profile must be explicit; no default home or consent is changed implicitly.
@main
struct HermesProfileProbe {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 4, ["status", "install", "uninstall"].contains(args[0]) else {
            throw NSError(domain: "HermesProfileProbe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Use: probe status|install|uninstall PROFILE PYTHON HOOK_EXECUTABLE"
            ])
        }
        let profile = URL(fileURLWithPath: args[1]).standardizedFileURL
        let python = URL(fileURLWithPath: args[2]).standardizedFileURL
        let binary = URL(fileURLWithPath: args[3]).standardizedFileURL
        let manager = HermesHookInstallationManager(profileDirectory: profile, pythonURL: python)
        let status: HermesHookInstallationStatus
        switch args[0] {
        case "install": status = try manager.install(hooksBinaryURL: binary)
        case "uninstall": status = try manager.uninstall()
        default: status = try manager.status(hooksBinaryURL: binary)
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "profile": profile.path,
            "configured": status.isInstalled,
            "currentCommand": status.isCurrent,
            "sourceConsentRecorded": status.hasConsent
        ], options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
