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
}
