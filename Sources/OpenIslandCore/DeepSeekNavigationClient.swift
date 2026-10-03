import Darwin
import Foundation

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
    public init() {}
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
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DeepSeekNavigationError.unavailable }
        defer { close(fd) }
        try disableSocketSigPipe(fd)
        try makeSocketNonBlocking(fd)
        try withUnixSocketAddress(path: path) { address, length in
            let result = Darwin.connect(fd, address, length)
            if result != 0 {
                guard errno == EINPROGRESS || errno == EALREADY || errno == EAGAIN else { throw DeepSeekNavigationError.unavailable }
                try Self.wait(fd: fd, event: Int16(POLLOUT), deadline: deadline)
                var error: Int32 = 0
                var size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw DeepSeekNavigationError.unavailable }
            }
        }
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
