import Testing
@testable import FlipcashCore

@Suite("Network")
struct NetworkTests {

    @Test("Core host resolves to the production endpoint")
    func hostForCore_mainNet_returnsProductionEndpoint() {
        #expect(Network.mainNet.hostForCore == "fc-v2.api.flipcash-infra.net")
    }

    @Test("Payments host resolves to the production endpoint")
    func hostForPayments_mainNet_returnsProductionEndpoint() {
        #expect(Network.mainNet.hostForPayments == "ocp-v2.api.flipcash-infra.net")
    }

    @Test("Port is 443")
    func port_mainNet_returns443() {
        #expect(Network.mainNet.port == 443)
    }
}
