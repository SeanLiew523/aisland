import Foundation

public struct ClaudeTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var tool: AgentTool
    public var title: String
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    public var updatedAt: Date
    public var firstSeenAt: Date?
    public var isSessionEnded: Bool
    public var jumpTarget: JumpTarget?
    public var claudeMetadata: ClaudeSessionMetadata?

    public init(
        sessionID: String,
        tool: AgentTool = .claudeCode,
        title: String,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        summary: String,
        phase: SessionPhase,
        updatedAt: Date,
        firstSeenAt: Date? = nil,
        isSessionEnded: Bool = false,
        jumpTarget: JumpTarget? = nil,
        claudeMetadata: ClaudeSessionMetadata? = nil
    ) {
        self.sessionID = sessionID
        self.tool = tool
        self.title = title
        self.origin = origin
        self.attachmentState = attachmentState
        self.summary = summary
        self.phase = phase
        self.updatedAt = updatedAt
        self.firstSeenAt = firstSeenAt
        self.isSessionEnded = isSessionEnded
        self.jumpTarget = jumpTarget
        self.claudeMetadata = claudeMetadata
    }

    public init(session: AgentSession) {
        self.init(
            sessionID: session.id,
            tool: session.tool,
            title: session.title,
            origin: session.origin,
            attachmentState: session.attachmentState,
            summary: session.summary,
            phase: session.phase,
            updatedAt: session.updatedAt,
            firstSeenAt: session.firstSeenAt,
            isSessionEnded: session.isSessionEnded,
            jumpTarget: session.jumpTarget,
            claudeMetadata: session.claudeMetadata
        )
    }

    public var session: AgentSession {
        var session = AgentSession(
            id: sessionID,
            title: title,
            tool: tool,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt,
            jumpTarget: jumpTarget,
            claudeMetadata: claudeMetadata
        )
        session.isSessionEnded = isSessionEnded
        return session
    }

    public var restorableSession: AgentSession {
        var session = session
        session.attachmentState = .stale
        return session
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case tool
        case title
        case origin
        case attachmentState
        case summary
        case phase
        case updatedAt
        case firstSeenAt
        case isSessionEnded
        case jumpTarget
        case claudeMetadata
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        // Only legacy records without a tag are Claude Code. An explicit
        // unknown/non-Claude-protocol tag must never impersonate that source.
        tool = container.contains(.tool) ? try container.decode(AgentTool.self, forKey: .tool) : .claudeCode
        guard tool.isClaudeCodeFork else {
            throw DecodingError.dataCorruptedError(forKey: .tool, in: container,
                debugDescription: "Unsupported Claude hook source")
        }
        title = try container.decode(String.self, forKey: .title)
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        attachmentState = try container.decodeIfPresent(SessionAttachmentState.self, forKey: .attachmentState) ?? .stale
        summary = try container.decode(String.self, forKey: .summary)
        phase = try container.decode(SessionPhase.self, forKey: .phase)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        firstSeenAt = try container.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        isSessionEnded = try container.decodeIfPresent(Bool.self, forKey: .isSessionEnded) ?? false
        jumpTarget = try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
        claudeMetadata = try container.decodeIfPresent(ClaudeSessionMetadata.self, forKey: .claudeMetadata)
    }

    public func encode(to encoder: any Encoder) throws {
        guard tool.isClaudeCodeFork else {
            throw EncodingError.invalidValue(tool, .init(codingPath: encoder.codingPath,
                debugDescription: "Unsupported Claude hook source"))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(tool, forKey: .tool)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(attachmentState, forKey: .attachmentState)
        try container.encode(summary, forKey: .summary)
        try container.encode(phase, forKey: .phase)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(firstSeenAt, forKey: .firstSeenAt)
        try container.encode(isSessionEnded, forKey: .isSessionEnded)
        try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
        try container.encodeIfPresent(claudeMetadata, forKey: .claudeMetadata)
    }
}

public extension ClaudeTrackedSessionRecord {
    var shouldRestoreToLiveState: Bool {
        tool.isClaudeCodeFork && origin != .demo && !isSessionEnded
    }
}

public final class ClaudeSessionRegistry: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        CodexSessionStore.defaultDirectoryURL
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("claude-session-registry.json")
    }

    public init(
        fileURL: URL = ClaudeSessionRegistry.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [ClaudeTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ClaudeTrackedSessionRecord].self, from: data)
    }

    public func save(_ records: [ClaudeTrackedSessionRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
