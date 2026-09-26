import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Card half of `test-vectors/link_detection.json`. Synced copy — a failure is fixed in the
/// canonical fixture and re-synced to both platforms, never edited here.
@Suite struct LinkCardClassifierTests {

    private final class BundleToken {}

    struct Vector: Decodable {
        struct Span: Decodable { let start: Int; let end: Int; let url: String }
        struct Card: Decodable { let kind: String; let url: String; let mint: String? }
        let name: String
        let spans: [Span]
        let card: Card?
        let note: String
    }

    struct Fixture: Decodable {
        let cardHosts: [String]
        let vectors: [Vector]
    }

    private func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: "link_detection", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Vectors iOS answers ahead of the canonical fixture, by name, with the card kind it gives.
    /// The fixture still says what Android does; each entry goes when the fixture is updated after
    /// Android ships the same card.
    private static let aheadOfFixture: [String: String] = [
        // Person cards: the fixture's "not in phase 1" (open decision 4).
        "tip-card-by-id": "user",
    ]

    @Test func cardEligibilityMatchesTheCrossPlatformVectors() throws {
        let classifier = LinkCardClassifier()

        for vector in try loadFixture().vectors {
            if let kind = Self.aheadOfFixture[vector.name] {
                let links = vector.spans.compactMap { span in
                    URL(string: span.url).map {
                        DetectedLink(range: NSRange(location: span.start, length: span.end - span.start), url: $0)
                    }
                }
                #expect(classifier.firstCard(in: links)?.kindName == kind, "vector `\(vector.name)` is ahead of the fixture")
                continue
            }

            let links = vector.spans.compactMap { span in
                URL(string: span.url).map {
                    DetectedLink(range: NSRange(location: span.start, length: span.end - span.start), url: $0)
                }
            }
            let actual = classifier.firstCard(in: links)

            guard let expected = vector.card else {
                #expect(actual == nil, "vector `\(vector.name)`: \(vector.note)")
                continue
            }

            guard let card = actual else {
                Issue.record("vector `\(vector.name)` produced no \(expected.kind) card: \(vector.note)")
                continue
            }
            #expect(card.kindName == expected.kind, "vector `\(vector.name)`: \(vector.note)")
            #expect(card.url.absoluteString == expected.url, "vector `\(vector.name)`: \(vector.note)")
            // The card carries the span it was built from, which is what the bubble cuts out of the
            // body. For a jump link that span is the wrapper, not `card.url`, so it is matched
            // against the detected spans rather than against the card's own target.
            #expect(
                links.contains { $0.range == card.range },
                "vector `\(vector.name)` card range \(card.range) is not one of its detected spans"
            )
            // The mint is read out of the path rather than matched against the URL, so the fixture
            // states it separately and the classifier has to agree.
            if case .token(let token) = card {
                #expect(token.mint.base58 == expected.mint, "vector `\(vector.name)`: \(vector.note)")
            }
        }
    }

    /// Not in the canonical fixture, which wraps only an allowlisted host. Android's classifier
    /// unwraps before the host gate for exactly this case; a gate on the wrapper alone lets the
    /// wrapper choose the host behind it, and `Route` classifies the target by path alone.
    @Test func aJumpWrapperCannotSmuggleAHostPastTheAllowlist() throws {
        let inner = "https://send.flipcash.com.evil.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"
        let wrapper = "https://jump.flipcash.com/#source=" + inner.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        )!
        let url = try #require(URL(string: wrapper))
        let link = DetectedLink(range: NSRange(location: 0, length: (wrapper as NSString).length), url: url)

        #expect(LinkCardClassifier().firstCard(in: [link]) == nil)
    }

    /// Not in the canonical fixture yet: Android refuses `/chat/` links until it ships the group
    /// card, and a shared vector would fail its copy until then.
    @Test func aGroupInviteLinkBecomesAGroupCard() throws {
        let text = "https://app.flipcash.com/chat/6f1c3a9e-2b7d-4e0a-9c55-1d2e3f405162"
        let url = try #require(URL(string: text))
        let link = DetectedLink(range: NSRange(location: 0, length: (text as NSString).length), url: url)

        let card = try #require(LinkCardClassifier().firstCard(in: [link]))
        guard case .group(let group) = card else {
            Issue.record("expected a group card, got \(card.kindName)")
            return
        }
        #expect(group.chatID == ConversationID(uuidString: "6f1c3a9e-2b7d-4e0a-9c55-1d2e3f405162"))
        #expect(group.url == url)
        #expect(group.range == link.range)
    }

    /// The Send Cash sheet over a chat opens a payment, not a group, so it stays a plain link.
    @Test func aChatSendCashLinkStaysALink() throws {
        let text = "https://app.flipcash.com/chat/6f1c3a9e-2b7d-4e0a-9c55-1d2e3f405162/send"
        let url = try #require(URL(string: text))
        let link = DetectedLink(range: NSRange(location: 0, length: (text as NSString).length), url: url)

        #expect(LinkCardClassifier().firstCard(in: [link]) == nil)
    }

    // MARK: - Person cards -

    private static func card(for text: String) throws -> LinkCard? {
        let url = try #require(URL(string: text))
        let link = DetectedLink(range: NSRange(location: 0, length: (text as NSString).length), url: url)
        return LinkCardClassifier().firstCard(in: [link])
    }

    private static let userID = "2b0b4d1e-9f3e-4c21-9f1a-6d5f7c8e9a0b"

    @Test func aHandleLinkBecomesAPersonCard() throws {
        let card = try #require(try Self.card(for: "https://flipcash.com/satoshi"))
        guard case .user(let user) = card else {
            Issue.record("expected a person card, got \(card.kindName)")
            return
        }
        #expect(user.identity == .username(try #require(Username("satoshi"))))
        #expect(user.linkedHandle == "@satoshi")
    }

    @Test(arguments: [
        "https://flipcash.com/2b0b4d1e-9f3e-4c21-9f1a-6d5f7c8e9a0b",
        "https://flipcash.com/tip/2b0b4d1e-9f3e-4c21-9f1a-6d5f7c8e9a0b",
    ])
    func anIDLinkBecomesAPersonCard(text: String) throws {
        let card = try #require(try Self.card(for: text))
        guard case .user(let user) = card else {
            Issue.record("expected a person card, got \(card.kindName)")
            return
        }
        #expect(user.identity == .userID(try #require(UserID(uuidString: Self.userID))))
        #expect(user.linkedHandle == nil)
    }

    /// `Route` reads any single-segment path as a handle, so only the host gate keeps an invite on
    /// another service from becoming a person card.
    @Test(arguments: [
        "https://discord.gg/x",
        "https://t.me/satoshi",
        "https://example.com/2b0b4d1e-9f3e-4c21-9f1a-6d5f7c8e9a0b",
        "https://example.com/tip/2b0b4d1e-9f3e-4c21-9f1a-6d5f7c8e9a0b",
    ])
    func aPersonShapedLinkOnAnotherHostStaysALink(text: String) throws {
        #expect(try Self.card(for: text) == nil)
    }

    /// A page the website serves is not somebody's handle, whatever case the link is typed in.
    @Test(arguments: [
        "https://flipcash.com/download",
        "https://flipcash.com/Privacy",
        "https://flipcash.com/terms",
        "https://flipcash.com/currencycreator",
        "https://flipcash.com/api",
    ])
    func aWebsitePageStaysALink(text: String) throws {
        #expect(try Self.card(for: text) == nil)
    }

    @Test func theHostAllowlistMatchesTheCrossPlatformFixture() throws {
        #expect(Set(try loadFixture().cardHosts) == Route.flipcashHosts)
    }
}

/// The fixture names a card's kind as a string; this is the one place that string meets the enum.
private extension LinkCard {
    var kindName: String {
        switch self {
        case .cash: "cash"
        case .token: "token"
        case .group: "group"
        case .user: "user"
        }
    }
}
