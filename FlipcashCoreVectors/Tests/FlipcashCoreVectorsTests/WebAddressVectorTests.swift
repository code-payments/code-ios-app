import Foundation
import Network
import Testing
@testable import FlipcashCore

/// Address half of `test-vectors/link_metadata.json`. The canonical copy lives in the
/// orchestrator repo; this one is synced. Never edit the fixture locally.
@Suite struct WebAddressVectorTests {

    struct Row: Decodable, Sendable, CustomTestStringConvertible {
        let address: String
        let isPublic: Bool
        let note: String

        enum CodingKeys: String, CodingKey {
            case address, note
            case isPublic = "public"
        }

        var testDescription: String { "\(address) — \(note)" }
    }

    struct Fixture: Decodable {
        let addresses: [Row]
    }

    static let rows: [Row] = (try? loadFixture().addresses) ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "link_metadata", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        #expect(try !Self.loadFixture().addresses.isEmpty)
    }

    @Test(arguments: rows)
    func addressMatchesTheCrossPlatformVector(_ row: Row) throws {
        let address: IPAddress = try #require(IPv4Address(row.address) ?? IPv6Address(row.address))
        #expect(WebLinks.isPublic(address) == row.isPublic)
    }

    /// D14: ranges agreed with Android ahead of canonical fixture rows. Only NAT64 is judged by its embedded IPv4.
    @Test(arguments: [
        ("64:ff9b::a00:1", false), ("64:ff9b::808:808", true),
        ("2002:a00:1::", false), ("2002:808:808::", false),
        ("::a00:1", false), ("::808:808", false),
        ("192.0.0.8", false), ("192.0.2.1", false), ("198.18.0.1", false), ("198.19.255.255", false),
        ("240.0.0.1", false), ("255.255.255.255", false), ("198.20.0.1", true), ("192.0.3.1", true),
    ])
    func agreedRangesAheadOfTheFixture(_ address: String, _ isPublic: Bool) throws {
        let parsed: IPAddress = try #require(IPv4Address(address) ?? IPv6Address(address))
        #expect(WebLinks.isPublic(parsed) == isPublic, "\(address)")
    }
}
