import Foundation

/// Compare semantic JSON so formatting alone cannot trigger a startup rewrite.
enum HookConfigurationComparison {
    static func sameJSON(_ lhs: Data?, _ rhs: Data?) -> Bool {
        guard let lhs, let rhs,
              let a = try? JSONSerialization.jsonObject(with: lhs) as? NSDictionary,
              let b = try? JSONSerialization.jsonObject(with: rhs) as? NSDictionary else { return false }
        return a == b
    }
}
