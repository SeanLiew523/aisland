import Darwin
import Foundation
import CryptoKit

public enum DeepSeekNavigationError: Error, LocalizedError {
    case missingIdentity, invalidResponse, sourceRejected, timedOut, unavailable
    public var errorDescription: String? {
        switch self {
        case .missingIdentity: "DeepSeek conversation identity is unavailable."
        case .invalidResponse: "DeepSeek returned a mismatched navigation receipt."
        case .sourceRejected: "DeepSeek could not dispatch conversation navigation."
        case .timedOut: "DeepSeek navigation timed out."
        case .unavailable: "The DeepSeek navigation plugin is unavailable."
        }
    }
}

/// A dispatch receipt proves the plugin called openSession(ID), not that the UI selected it.
public struct DeepSeekNavigationClient: Sendable {
    public struct Request: Codable, Sendable {
        public var version = 1
        public var action = "openSession"
        public var requestID: String
        public var profileID: String
        public var sessionID: String
        enum CodingKeys: String, CodingKey {
            case version, action
            case requestID = "request_id", profileID = "profile_id", sessionID = "session_id"
        }
        public init(profileID: String, sessionID: String, requestID: String = UUID().uuidString) {
            self.profileID = profileID; self.sessionID = sessionID; self.requestID = requestID
        }
    }
    private struct Receipt: Decodable {
        var version: Int
        var requestID: String
        var profileID: String
        var sessionID: String
        var status: String
        enum CodingKeys: String, CodingKey {
            case version, status
            case requestID = "request_id", profileID = "profile_id", sessionID = "session_id"
        }
    }
    private let sourceVerifier: @Sendable (Int32, String) -> Bool
    public init() { sourceVerifier = Self.trustedSource }
    init(sourceVerifier: @escaping @Sendable (Int32, String) -> Bool) { self.sourceVerifier = sourceVerifier }

    private struct EndpointProof: Decodable {
        var version: Int
        var source: String
        var path: String
        var requested_path: String
        var profile_sha256: String
        var uid: UInt32
        var dev: Int64
        var ino: UInt64
        var bind_directory: String
        var directory_dev: Int64
        var directory_ino: UInt64
        var source_pid: Int32
        var executable_path: String
    }
    private struct AdmittedEndpoint {
        var proof: EndpointProof
        var filename: String
        var fileIdentity: stat
        var socketIdentity: stat
        var directoryIdentity: stat
    }
    private static func identity(_ path: String) -> stat? {
        var value = stat()
        return lstat(path, &value) == 0 ? value : nil
    }
    private static func same(_ a: stat, _ b: stat?) -> Bool {
        guard let b else { return false }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode
    }
    private static func trustedSource(pid: Int32, executable: String) -> Bool {
        let bundleURL = URL(fileURLWithPath: "/Applications/DeepSeek Harness.app")
        guard pid > 0, let bundle = Bundle(url: bundleURL), bundle.bundleIdentifier == "com.deepseek.dsh",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "0.2.0-rc.2",
              bundle.executableURL?.path == executable else { return false }
        var bytes = [UInt8](repeating: 0, count: 4096)
        guard bytes.withUnsafeMutableBytes({ proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }) > 0 else { return false }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) == executable
    }
    private func admit(path: String, profile: String) throws -> AdmittedEndpoint {
        guard path.hasPrefix("/"), URL(fileURLWithPath: path).standardizedFileURL.path == path else { throw DeepSeekNavigationError.unavailable }
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard let parent = Self.identity(parentPath), parent.st_mode & S_IFMT == S_IFDIR,
              parent.st_uid == getuid(), parent.st_mode & 0o022 == 0 else { throw DeepSeekNavigationError.unavailable }
        let locator = path + ".aisland-current.json"
        let filename = Self.identity(locator) == nil ? path + ".aisland-owner.json" : locator
        guard let file = Self.identity(filename), file.st_mode & S_IFMT == S_IFREG,
              file.st_mode & 0o777 == 0o600, file.st_uid == getuid(), file.st_nlink == 1,
              file.st_size > 0, file.st_size <= 2048 else { throw DeepSeekNavigationError.unavailable }
        let fd = open(filename, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DeepSeekNavigationError.unavailable }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, Self.same(file, opened) else { throw DeepSeekNavigationError.unavailable }
        var bytes = [UInt8](repeating: 0, count: 2049)
        let count = read(fd, &bytes, bytes.count)
        guard count > 0, count <= 2048,
              let proof = try? JSONDecoder().decode(EndpointProof.self, from: Data(bytes.prefix(count))),
              proof.version == 1, proof.source == "@aisland/deepseek-harness-plugin", proof.uid == getuid(),
              proof.profile_sha256 == SHA256.hash(data: Data(profile.utf8)).map({ String(format: "%02x", $0) }).joined(),
              proof.path.hasPrefix("/"), proof.requested_path.hasPrefix("/"),
              (filename == locator ? proof.requested_path == path : proof.path == path),
              URL(fileURLWithPath: proof.path).standardizedFileURL.path == proof.path,
              URL(fileURLWithPath: proof.requested_path).standardizedFileURL.path == proof.requested_path,
              URL(fileURLWithPath: proof.path).deletingLastPathComponent().path == parentPath,
              URL(fileURLWithPath: proof.requested_path).deletingLastPathComponent().path == parentPath,
              URL(fileURLWithPath: proof.bind_directory).deletingLastPathComponent().path == parentPath,
              URL(fileURLWithPath: proof.bind_directory).lastPathComponent.range(of: #"^\.ds-[a-zA-Z0-9]+$"#, options: .regularExpression) != nil,
              let directory = Self.identity(proof.bind_directory), directory.st_mode & S_IFMT == S_IFDIR,
              directory.st_mode & 0o777 == 0o700, directory.st_uid == getuid(),
              Int64(directory.st_dev) == proof.directory_dev, UInt64(directory.st_ino) == proof.directory_ino,
              let socket = Self.identity(proof.path), socket.st_mode & S_IFMT == S_IFSOCK,
              socket.st_mode & 0o777 == 0o600, socket.st_uid == getuid(),
              Int64(socket.st_dev) == proof.dev, UInt64(socket.st_ino) == proof.ino,
              Self.same(socket, Self.identity(proof.bind_directory + "/s")),
              Self.same(file, Self.identity(filename)), sourceVerifier(proof.source_pid, proof.executable_path)
        else { throw DeepSeekNavigationError.unavailable }
        return AdmittedEndpoint(proof: proof, filename: filename, fileIdentity: file, socketIdentity: socket, directoryIdentity: directory)
    }

    public static func validate(_ data: Data, for request: Request) throws {
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.version == 1,
              receipt.requestID == request.requestID, receipt.profileID == request.profileID,
              receipt.sessionID == request.sessionID else { throw DeepSeekNavigationError.invalidResponse }
        guard receipt.status == "dispatched" else { throw DeepSeekNavigationError.sourceRejected }
    }
    public func dispatch(target: JumpTarget, timeout: TimeInterval = 2,
                         environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let deadline = Date().addingTimeInterval(max(0.01, timeout))
        guard let session = target.appConversationID, !session.isEmpty,
              let profile = target.runtimeProfileID, !profile.isEmpty else { throw DeepSeekNavigationError.missingIdentity }
        let request = Request(profileID: profile, sessionID: session)
        var data = try JSONEncoder().encode(request); data.append(10)
        let path = target.runtimeNavigationSocketPath ?? environment["OPEN_ISLAND_DEEPSEEK_NAVIGATION_SOCKET_PATH"]
            ?? BridgeSocketLocation.currentURL(environment: environment).deletingLastPathComponent().appendingPathComponent("deepseek-navigation.sock").path
        // Admit the current owned endpoint before sending anything, including when
        // an old cached target points at an unknown but connectable legacy socket.
        let endpoint = try admit(path: path, profile: profile)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DeepSeekNavigationError.unavailable }
        defer { close(fd) }
        try disableSocketSigPipe(fd)
        try makeSocketNonBlocking(fd)
        try withUnixSocketAddress(path: endpoint.proof.path) { address, length in
            let result = Darwin.connect(fd, address, length)
            if result != 0 {
                guard errno == EINPROGRESS || errno == EALREADY || errno == EAGAIN else { throw DeepSeekNavigationError.unavailable }
                try Self.wait(fd: fd, event: Int16(POLLOUT), deadline: deadline)
                var error: Int32 = 0
                var size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw DeepSeekNavigationError.unavailable }
            }
        }
        var peerPID: Int32 = 0
        var peerSize = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &peerSize) == 0,
              peerPID == endpoint.proof.source_pid,
              sourceVerifier(peerPID, endpoint.proof.executable_path),
              Self.same(endpoint.fileIdentity, Self.identity(endpoint.filename)),
              Self.same(endpoint.socketIdentity, Self.identity(endpoint.proof.path)),
              Self.same(endpoint.directoryIdentity, Self.identity(endpoint.proof.bind_directory))
        else { throw DeepSeekNavigationError.unavailable }
        try Self.send(data, fd: fd, deadline: deadline)
        var response = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while Date() < deadline {
            try Self.wait(fd: fd, event: Int16(POLLIN), deadline: deadline)
            let count = read(fd, &bytes, bytes.count)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard count > 0 else { throw DeepSeekNavigationError.unavailable }
            response.append(contentsOf: bytes.prefix(count))
            guard response.count <= 16_384 else { throw DeepSeekNavigationError.invalidResponse }
            if let newline = response.firstIndex(of: 10) {
                try Self.validate(Data(response.prefix(upTo: newline)), for: request)
                return
            }
        }
        throw DeepSeekNavigationError.timedOut
    }
    /// All phases share one deadline, including a full peer send buffer.
    static func send(_ data: Data, fd: Int32, deadline: Date) throws {
        var sent = 0
        while sent < data.count {
            guard Date() < deadline else { throw DeepSeekNavigationError.timedOut }
            let count = data.withUnsafeBytes { bytes in
                Darwin.write(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if count > 0 { sent += count; continue }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                try wait(fd: fd, event: Int16(POLLOUT), deadline: deadline)
                continue
            }
            throw DeepSeekNavigationError.unavailable
        }
    }
    private static func wait(fd: Int32, event: Int16, deadline: Date) throws {
        while Date() < deadline {
            var descriptor = pollfd(fd: fd, events: event, revents: 0)
            let remaining = max(1, Int32(min(100, deadline.timeIntervalSinceNow * 1000)))
            let ready = poll(&descriptor, 1, remaining)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            guard ready > 0, descriptor.revents & event != 0 else { throw DeepSeekNavigationError.unavailable }
            return
        }
        throw DeepSeekNavigationError.timedOut
    }

}
