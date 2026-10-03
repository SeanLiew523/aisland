import Foundation
import OpenIslandCore

enum IslandSurface: Equatable {
    case sessionList(actionableSessionID: String? = nil)

    var sessionID: String? {
        switch self {
        case let .sessionList(actionableSessionID):
            actionableSessionID
        }
    }

    var isNotificationCard: Bool {
        sessionID != nil
    }

    func notificationSoundCategory(for session: AgentSession?) -> NotificationSoundCategory? {
        guard let session, session.id == sessionID, matchesCurrentState(of: session) else { return nil }
        switch session.phase {
        case .waitingForApproval: return .approval
        case .waitingForAnswer: return .answer
        case .completed:
            return session.runtimeOutcome == nil || session.runtimeOutcome == .succeeded ? .completed : nil
        case .running: return nil
        }
    }

    func autoDismissesWhenPresentedAsNotification(session: AgentSession?) -> Bool {
        guard sessionID != nil else { return false }
        return session?.phase == .completed
    }

    static func notificationSurface(for event: AgentEvent) -> IslandSurface? {
        switch event {
        case let .permissionRequested(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .questionAsked(payload):
            .sessionList(actionableSessionID: payload.sessionID)
        case let .sessionCompleted(payload):
            payload.isInterrupt == true ? nil : .sessionList(actionableSessionID: payload.sessionID)
        default:
            nil
        }
    }

    func matchesCurrentState(of session: AgentSession?) -> Bool {
        guard sessionID != nil else {
            return true
        }

        guard let session else {
            return false
        }

        switch session.phase {
        case .waitingForApproval:
            return session.permissionRequest != nil
        case .waitingForAnswer:
            return session.questionPrompt != nil
        case .completed:
            return true
        case .running:
            return false
        }
    }
}
