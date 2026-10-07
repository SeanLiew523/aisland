import Foundation
import Darwin

/// Resolves open-file *path metadata* from an exact, already-admitted Desktop PID.
/// No argv, environment, session rows, auth files or SQLite contents are read.
public enum MiniMaxCodeActiveDataDirectory {
    public struct ProcessIdentity: Equatable, Sendable {
        public var pid: Int32
        public var parentPID: UInt32
        public var executablePath: String
        public var startedAt: UInt64
    }
    public static func snapshot(_ pid: Int32) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        guard pid > 1, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        var bytes = [CChar](repeating: 0, count: 4096)
        guard bytes.withUnsafeMutableBytes({ proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }) > 0 else { return nil }
        return ProcessIdentity(pid: pid, parentPID: info.pbi_ppid, executablePath: String(cString: bytes),
            startedAt: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }
    public static func resolve(processID: Int32, appURL: URL) throws -> URL? {
        let prefix = appURL.resolvingSymlinksInPath().path + "/Contents/"
        guard let root = snapshot(processID), root.executablePath.hasPrefix(prefix) else { return nil }
        var pids = [Int32](repeating: 0, count: 16_384)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, count < pids.count else { return nil }
        let values = pids.prefix(Int(count)).compactMap(snapshot).filter { $0.executablePath.hasPrefix(prefix) }
        let admitted = descendantProcesses(root: root, candidates: values)
        guard !admitted.isEmpty, admitted.count <= 32 else { return nil }
        let ids = admitted.map { String($0.pid) }.joined(separator: ",")
        let data = try ConnectionProcessRunner.run(URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-a", "-p", ids, "-Fn"], environment: ["PATH": "/usr/bin:/bin:/usr/sbin", "LC_ALL": "C"], timeout: 2)
        guard snapshot(processID) == root, admitted.allSatisfy({ snapshot($0.pid) == $0 }) else { return nil }
        return uniqueDirectory(lsofMetadata: String(decoding: data, as: UTF8.self))
    }
    public static func descendantProcesses(root: ProcessIdentity, candidates: [ProcessIdentity]) -> [ProcessIdentity] {
        var admitted = [root]
        for _ in 0..<8 {
            let ids = Set(admitted.map(\.pid))
            let next = candidates.filter { !ids.contains($0.pid) && $0.parentPID <= UInt32(Int32.max)
                && ids.contains(Int32($0.parentPID)) && $0.startedAt >= root.startedAt }
            if next.isEmpty { break }; admitted += next
            if admitted.count > 32 { return [] }
        }
        return admitted
    }
    public static func uniqueDirectory(lsofMetadata: String) -> URL? {
        let suffix = "/v2/sqlite/runtime-state.sqlite"
        let paths = Set(lsofMetadata.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("n/"), line.hasSuffix(suffix) else { return nil }
            let path = String(line.dropFirst().dropLast(suffix.count))
            guard !path.isEmpty, path.utf8.count <= 4096,
                  !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  URL(fileURLWithPath: path).standardizedFileURL.path == path else { return nil }
            return path
        })
        guard paths.count == 1, let path = paths.first else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
