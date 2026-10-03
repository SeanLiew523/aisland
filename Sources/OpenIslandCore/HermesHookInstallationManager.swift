import Foundation

public struct HermesHookInstallationStatus: Equatable, Sendable {
    public var configURL: URL
    public var isInstalled: Bool
    public var isCurrent: Bool
    public var hasConsent: Bool
}
public enum HermesHookInstallationError: Error, LocalizedError, Equatable {
    case unavailablePython, invalidConfiguration(String), configurationChanged, missingBinary
    public var errorDescription: String? {
        switch self {
        case .unavailablePython: "Hermes Python with PyYAML is unavailable. Select its Python interpreter."
        case let .invalidConfiguration(reason): "Hermes configuration could not be updated: \(reason)"
        case .configurationChanged: "Hermes configuration changed during setup. Refresh and retry."
        case .missingBinary: "The AIsland hook binary is unavailable."
        }
    }
}

public struct HermesHookInstallationManager: Sendable {
    public let profileDirectory: URL
    public let pythonURL: URL
    public var configURL: URL { profileDirectory.appendingPathComponent("config.yaml") }
    public var manifestURL: URL { profileDirectory.appendingPathComponent("aisland-hooks.json") }
    private static let events = ["pre_llm_call", "on_session_end"]
    public static var defaultProfileDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["HERMES_HOME"] ?? NSHomeDirectory() + "/.hermes")
    }
    public static var defaultPythonURL: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPEN_ISLAND_HERMES_PYTHON"] ?? NSHomeDirectory() + "/.hermes/hermes-agent/venv/bin/python")
    }
    public init(profileDirectory: URL = Self.defaultProfileDirectory, pythonURL: URL = Self.defaultPythonURL) {
        self.profileDirectory = profileDirectory.standardizedFileURL
        self.pythonURL = pythonURL.standardizedFileURL
    }
    public func status(hooksBinaryURL: URL? = nil) throws -> HermesHookInstallationStatus {
        let old = try manifestCommand()
        let result = try transform(action: "status", command: old ?? "", previousCommand: old ?? "")
        let installed = result.installed && old != nil
        let expected = hooksBinaryURL.map(command(for:))
        let consent = consentExists(command: old)
        return HermesHookInstallationStatus(configURL: configURL, isInstalled: installed,
            isCurrent: installed && (expected == nil || expected == old), hasConsent: consent)
    }
    @discardableResult public func install(hooksBinaryURL: URL) throws -> HermesHookInstallationStatus {
        guard FileManager.default.isExecutableFile(atPath: hooksBinaryURL.path) else { throw HermesHookInstallationError.missingBinary }
        let command = command(for: hooksBinaryURL)
        let previous = try manifestCommand() ?? ""
        let result = try transform(action: "install", command: command, previousCommand: previous)
        try writeConfiguration(result)
        let manifest = try JSONSerialization.data(withJSONObject: ["version": 1, "command": command])
        try manifest.write(to: manifestURL, options: .atomic)
        return try status(hooksBinaryURL: hooksBinaryURL)
    }
    @discardableResult public func uninstall() throws -> HermesHookInstallationStatus {
        guard let previous = try manifestCommand() else { return try status() }
        let result = try transform(action: "uninstall", command: "", previousCommand: previous)
        try writeConfiguration(result)
        try FileManager.default.removeItem(at: manifestURL)
        // Hermes owns consent records; leave unrelated and historical approvals untouched.
        return try status()
    }
    private func command(for binary: URL) -> String {
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return "\(quote(binary.path)) --source hermes --profile-id \(quote(profileDirectory.path))"
    }
    private func manifestCommand() throws -> String? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        guard object?["version"] as? Int == 1, let command = object?["command"] as? String, !command.isEmpty else {
            throw HermesHookInstallationError.invalidConfiguration("Invalid AIsland ownership manifest.")
        }
        return command
    }
    private func consentExists(command: String?) -> Bool {
        guard let command, let data = try? Data(contentsOf: profileDirectory.appendingPathComponent("shell-hooks-allowlist.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let approvals = root["approvals"] as? [[String: Any]] else { return false }
        return Self.events.allSatisfy { event in approvals.contains { $0["event"] as? String == event && $0["command"] as? String == command } }
    }
    private struct Transform {
        var original: Data
        var updated: Data
        var installed: Bool
    }
    private func transform(action: String, command: String, previousCommand: String) throws -> Transform {
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else { throw HermesHookInstallationError.unavailablePython }
        let original = try readConfiguration()
        let input = Pipe(); let output = Pipe(); let errors = Pipe(); let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", Self.yamlTransform, action, command, previousCommand]
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
        // Configs may exceed pipe capacity: send asynchronously while draining output.
        let writer = input.fileHandleForWriting
        DispatchQueue.global().async { try? writer.write(contentsOf: original); try? writer.close() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["config"] as? String, let installed = root["installed"] as? Bool else {
            // Never expose config values in diagnostics. Python errors are sanitized by the script.
            let reason = String(data: errorData, encoding: .utf8) ?? "YAML parser unavailable"
            throw HermesHookInstallationError.invalidConfiguration(String(reason.prefix(160)))
        }
        return Transform(original: original, updated: Data(text.utf8), installed: installed)
    }
    private func readConfiguration() throws -> Data {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return Data() }
        let attributes = try FileManager.default.attributesOfItem(atPath: configURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw HermesHookInstallationError.invalidConfiguration("config.yaml must be a regular file.")
        }
        return try Data(contentsOf: configURL)
    }
    private func writeConfiguration(_ result: Transform) throws {
        let current = try readConfiguration()
        guard current == result.original else { throw HermesHookInstallationError.configurationChanged }
        guard result.updated != current else { return }
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let permissions = (try? FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions]) ?? 0o600
        if !current.isEmpty {
            let backup = profileDirectory.appendingPathComponent("config.yaml.aisland-backup")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try current.write(to: backup, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
        }
        try result.updated.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: configURL.path)
    }
    // Only the hooks mapping is re-serialized; unrelated config and comments retain original bytes.
    private static let yamlTransform = #"""
import json, sys
try:
    import yaml
    from yaml.nodes import MappingNode
    text = sys.stdin.read()
    action, command, previous = sys.argv[1:]
    class StrictLoader(yaml.SafeLoader): pass
    def mapping(loader, node, deep=False):
        result = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            if key in result: raise ValueError('Duplicate YAML key')
            result[key] = loader.construct_object(value_node, deep=deep)
        return result
    StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
    cfg = yaml.load(text, Loader=StrictLoader) if text.strip() else {}
    if cfg is None: cfg = {}
    if not isinstance(cfg, dict): raise ValueError('Config root must be a mapping')
    hooks = cfg.get('hooks', {})
    if hooks is None: hooks = {}
    if not isinstance(hooks, dict): raise ValueError('hooks must be a mapping')
    events = ['pre_llm_call', 'on_session_end']
    for event in events:
        if hooks.get(event) is not None and not isinstance(hooks[event], list):
            raise ValueError('Lifecycle hook entries must be lists')
    installed = bool(command) and all(any(isinstance(e, dict) and e.get('command') == command
        for e in hooks.get(event, []) or []) for event in events)
    if action == 'status':
        print(json.dumps({'config': text, 'installed': installed})); sys.exit(0)
    for event in events:
        entries = hooks.get(event, []) or []
        hooks[event] = [e for e in entries if not (isinstance(e, dict) and e.get('command') in {previous, command} and e.get('command'))]
        if action == 'install': hooks[event].append({'command': command, 'timeout': 3, 'fail_closed': False})
        if not hooks[event]: hooks.pop(event, None)
    node = yaml.compose(text) if text.strip() else None
    if isinstance(node, MappingNode) and node.flow_style: raise ValueError("Flow root unsupported")
    replacement = yaml.safe_dump({'hooks': hooks}, sort_keys=False, allow_unicode=True) if hooks else ''
    if isinstance(node, MappingNode):
        target = next(((k, v) for k, v in node.value if k.value == 'hooks'), None)
        if target:
            key, value = target
            if any(getattr(e, "anchor", None) for e in yaml.parse(text) if key.start_mark.index <= e.start_mark.index < value.end_mark.index):
                raise ValueError("Anchored hooks unsupported")
            text = text[:key.start_mark.index] + replacement + text[value.end_mark.index:]
        elif replacement: text += ('\n' if text and not text.endswith('\n') else '') + replacement
    elif replacement: text += replacement
    print(json.dumps({'config': text, 'installed': action == 'install'}))
except Exception as error:
    safe = str(error) if isinstance(error, ValueError) else 'invalid YAML or unavailable PyYAML'
    sys.stderr.write(type(error).__name__ + ': ' + safe)
    sys.exit(1)
"""#
}
