import Foundation
import Darwin

// Standalone macOS helper, compiled outside the source Plugin package.
// Reads only parent PID, executable path, birth time and controlling terminal.
// Never reads process arguments, environment, file descriptors or task content.
struct Ancestor: Codable {
    var pid: Int32
    var parentPID: UInt32
    var executablePath: String
    var startedAtMs: Double
    var tty: String?
}
struct DesktopApp: Codable { var path: String; var bundleID: String; var version: String }
struct Result: Codable { var schemaVersion = 1; var ancestors: [Ancestor]; var desktopApp: DesktopApp? }
func snapshot(_ pid: Int32) -> Ancestor? {
    var info = proc_bsdinfo()
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
          info.pbi_pid == UInt32(pid) else { return nil }
    var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let count = bytes.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
    guard count > 0 else { return nil }
    let path = bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    let startedAt = Double(info.pbi_start_tvsec) * 1000 + Double(info.pbi_start_tvusec) / 1000
    guard path.hasPrefix("/"), startedAt > 0, startedAt.isFinite else { return nil }
    var tty: String?
    if info.pbi_flags & UInt32(PROC_FLAG_CTTY) != 0, info.e_tdev != UInt32.max, info.e_tdev != 0,
       let device = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR) {
        let name = String(cString: device)
        if name.hasPrefix("tty"), name.utf8.count <= 100, !name.contains("/") { tty = "/dev/" + name }
    }
    return Ancestor(pid: pid, parentPID: info.pbi_ppid, executablePath: path, startedAtMs: startedAt, tty: tty)
}
func result() -> Result {
    guard CommandLine.arguments.count == 3, let initial = Int32(CommandLine.arguments[1]), initial > 1,
          CommandLine.arguments[2].hasPrefix("/"), CommandLine.arguments[2].hasSuffix(".app") else {
        return Result(ancestors: [], desktopApp: nil)
    }
    var ancestors: [Ancestor] = []; var pid = initial; var visited = Set<Int32>()
    for _ in 0..<16 {
        guard pid > 1, !visited.contains(pid), let value = snapshot(pid) else { break }
        visited.insert(pid); ancestors.append(value)
        guard value.parentPID <= UInt32(Int32.max) else { break }
        pid = Int32(value.parentPID)
    }
    // Recheck the initial identity after walking to detect exit/reparent/PID reuse.
    guard let first = ancestors.first, let confirmed = snapshot(initial),
          first.startedAtMs == confirmed.startedAtMs, first.parentPID == confirmed.parentPID else {
        return Result(ancestors: [], desktopApp: nil)
    }
    let path = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.resolvingSymlinksInPath().path
    let app: DesktopApp?
    if let bundle = Bundle(path: path), let id = bundle.bundleIdentifier,
       let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
        app = DesktopApp(path: path, bundleID: id, version: version)
    } else { app = nil }
    return Result(ancestors: ancestors, desktopApp: app)
}
if let data = try? JSONEncoder().encode(result()) {
    FileHandle.standardOutput.write(data)
}
