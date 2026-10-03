import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeServerSocketIsolationTests {
    @Test func uniqueListenerLeavesProductionAndLegacySocketsUntouched() throws {
        func identity(_ url: URL) -> String {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "absent" }
            return "\(attributes[.systemFileNumber] ?? "unknown"):\(attributes[.type] ?? "unknown")"
        }
        let locations = [BridgeSocketLocation.defaultURL, BridgeSocketLocation.legacyURL]
        let before = locations.map(identity)
        let unique = BridgeSocketLocation.uniqueTestURL()
        defer { try? FileManager.default.removeItem(at: unique) }
        let server = BridgeServer(socketURL: unique)
        try server.start()
        #expect(locations.map(identity) == before)
        let client = BridgeCommandClient(socketURL: unique)
        #expect(try client.send(.registerClient(role: .observer), timeout: 1) == .acknowledged)
        server.stop()
        #expect(locations.map(identity) == before)

    }
}
