//
//  FlipcashPuppetHostSeedTests.swift
//  FlipcashCoreVectorsTests
//

import Foundation
import Testing
import FlipcashPuppet
import FlipcashStore

/// `launch` picks a seed by name: an unknown one is `bad_input`, a non-string is `bad_request`,
/// and a launch that names none gets the default whatever the last launch used.
@Suite("Puppet host seeds")
struct FlipcashPuppetHostSeedTests {

    @Test("Each seed's balances are what the Chats README says New Chat reads")
    func seedBalances() throws {
        #expect(try #require(ChatsPuppetHost.seeds["default"]).communityCurrencies().isEmpty)
        let holder = try #require(ChatsPuppetHost.seeds["community-holder"]).communityCurrencies()
        #expect(holder.map(\.stored.symbol) == ["PUPPET"])
        let value = try #require(holder.first).exchangedFiat.nativeAmount.value
        #expect(abs(value - 5) < Decimal(string: "0.01")!, "PUPPET is worth \(value), not about $5")
    }

    @Test("A launch without a seed after a seeded one gets the default")
    func seedDoesNotCarry() {
        var host = FlipcashPuppetHost()
        #expect(communityRow(&host, seed: "community-holder") == "NewCommunityGroup")
        #expect(communityRow(&host, seed: nil) == "NoCommunityCurrencies")
    }

    @Test("An unknown seed is bad_input and names the known ones")
    func unknownSeed() {
        var host = FlipcashPuppetHost()
        let response = host.handle(launch(seed: .string("nope")))
        #expect(code(response) == "bad_input")
        #expect(message(response)?.contains("community-holder") == true)
    }

    @Test("A seed that isn't a string is bad_request")
    func nonStringSeed() {
        var host = FlipcashPuppetHost()
        #expect(code(host.handle(launch(seed: .number(1)))) == "bad_request")
    }

    /// Launches with `seed`, opens New Chat's community row and returns the top screen's name.
    private func communityRow(_ host: inout FlipcashPuppetHost, seed: String?) -> String? {
        _ = host.handle(launch(seed: seed.map(JSON.string)))
        _ = host.handle(.object(["cmd": .string("do"), "action": .string("NewChatOpened")]))
        let response = host.handle(.object(["cmd": .string("do"), "action": .string("CommunityGroupOpened")]))
        guard case .object(let obj) = response, case .array(let path)? = obj["path"],
              case .string(let top)? = path.last else { return nil }
        return top
    }

    private func launch(seed: JSON?) -> JSON {
        var req: [String: JSON] = ["cmd": .string("launch"), "route": .string("/tab/chats")]
        if let seed { req["seed"] = seed }
        return .object(req)
    }

    private func code(_ response: JSON) -> String? {
        guard case .object(let obj) = response, case .object(let err)? = obj["error"],
              case .string(let code)? = err["code"] else { return nil }
        return code
    }

    private func message(_ response: JSON) -> String? {
        guard case .object(let obj) = response, case .object(let err)? = obj["error"],
              case .string(let message)? = err["message"] else { return nil }
        return message
    }
}
