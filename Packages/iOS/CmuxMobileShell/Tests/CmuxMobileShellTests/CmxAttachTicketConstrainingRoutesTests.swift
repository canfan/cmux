import CMUXMobileCore
import Testing
@testable import CmuxMobileShell

@Suite("Attach ticket route constraints")
struct CmxAttachTicketConstrainingRoutesTests {
    @Test func preservesLocalPairingAuthorityMarker() throws {
        let originalRoute = try CmxAttachRoute(
            id: "tailscale",
            kind: .tailscale,
            endpoint: .hostPort(host: "100.64.0.5", port: 58465),
            priority: 10
        )
        let constrainedRoute = try CmxAttachRoute(
            id: "tailscale_2",
            kind: .tailscale,
            endpoint: .hostPort(host: "fd7a:115c:a1e0::5", port: 58465),
            priority: 20
        )
        let ticket = try CmxAttachTicket(
            workspaceID: "",
            terminalID: nil,
            macDeviceID: "mac-1",
            macDisplayName: nil,
            routes: [originalRoute, constrainedRoute],
            authToken: "local-capability",
            localPairing: true
        )

        let constrained = try ticket.constrainingRoutes(
            to: [constrainedRoute],
            fallbackDisplayName: "Mac"
        )

        #expect(constrained.localPairing)
        #expect(constrained.authToken == ticket.authToken)
        #expect(constrained.routes == [constrainedRoute])
    }
}
