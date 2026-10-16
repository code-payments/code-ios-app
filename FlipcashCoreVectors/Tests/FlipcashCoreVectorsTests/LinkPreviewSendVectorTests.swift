import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/link_preview_send.json`: the checks a sender runs before attaching a link preview.
/// The canonical copy lives in the orchestrator repo; this one is synced. Never edit it locally.
@Suite struct LinkPreviewSendVectorTests {

    struct WholeLink: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let url: String
        let accepted: Bool
        var testDescription: String { name }
    }

    struct Cleaning: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let raw: String
        let expected: String?
        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let wholeLink: [WholeLink]
        let title: [Cleaning]
        let description: [Cleaning]
    }

    static let fixture: Fixture? = try? loadFixture()
    static let wholeLinks = fixture?.wholeLink ?? []
    static let titles = fixture?.title ?? []
    static let descriptions = fixture?.description ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "link_preview_send", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        let fixture = try Self.loadFixture()
        #expect(!fixture.wholeLink.isEmpty && !fixture.title.isEmpty && !fixture.description.isEmpty)
    }

    @Test(arguments: wholeLinks)
    func wholeLinkMatches(_ v: WholeLink) {
        #expect(LinkPreviewSendChecks.isWholeLink(url: v.url, in: v.text) == v.accepted)
    }

    @Test(arguments: titles)
    func titleMatches(_ v: Cleaning) {
        #expect(LinkPreviewSendChecks.cleanTitle(v.raw) == v.expected)
    }

    @Test(arguments: descriptions)
    func descriptionMatches(_ v: Cleaning) {
        #expect(LinkPreviewSendChecks.cleanDescription(v.raw) == (v.expected ?? ""))
    }
}
