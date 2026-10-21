import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/reaction-boost-split.json`: which intent a reaction boost uses and each payee's
/// cents. The canonical copy lives in the orchestrator repo; this one is synced. Never edit it locally.
@Suite struct ReactionBoostSplitVectorTests {

    struct Fixture: Decodable, Sendable {
        let creatorPercent: UInt64
        let minimumShare: String
        let minimumTwoPayeeTotal: String
        let vectors: [Vector]
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        struct Expected: Decodable, Sendable {
            struct Payee: Decodable, Sendable {
                let role: String
                let nativeAmount: String
            }
            let intent: String
            let payees: [Payee]?
            let expectedError: String?
        }

        let name: String
        let payer: String
        let messageSender: String
        let total: String
        let note: String
        let expected: Expected

        var testDescription: String { name }
    }

    static let creator = UserID()
    static let member = UserID()
    static let otherMember = UserID()

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "reaction-boost-split", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    @Test func constantsMatchTheCrossPlatformVectors() throws {
        #expect(Self.fixture.creatorPercent == ReactionBoostSplit.creatorPercent)
        #expect(try Self.cents(Self.fixture.minimumShare) == ReactionBoostSplit.minimumShareCents)
        #expect(try Self.cents(Self.fixture.minimumTwoPayeeTotal) == ReactionBoostSplit.minimumTwoPayeeCents)
    }

    @Test(arguments: fixture.vectors)
    func splitMatchesTheCrossPlatformVectors(vector: Vector) throws {
        let messageSender = vector.messageSender == "creator" ? Self.creator : Self.otherMember
        let payer: UserID = switch vector.payer {
        case "creator": Self.creator
        case "sender": messageSender
        default: Self.member
        }
        let total = try Self.cents(vector.total)
        let result = Result { () throws(ReactionBoostSplit.Rejection) in
            try ReactionBoostSplit.split(totalCents: total, payer: payer, messageSender: messageSender, creator: Self.creator)
        }

        switch vector.expected.intent {
        case "rejected":
            let expected: ReactionBoostSplit.Rejection = vector.expected.expectedError == "self-boost" ? .selfBoost : .shareBelowMinimum
            #expect(throws: expected, "\(vector.note)") { try result.get() }

        case "SendPublicPayment", "SendPublicMultiPayment":
            let split = try result.get()
            let isMulti = if case .multi = split { true } else { false }
            #expect(isMulti == (vector.expected.intent == "SendPublicMultiPayment"), "\(vector.note)")

            let payees = try #require(vector.expected.payees)
            #expect(split.shares.count == payees.count)
            for (share, payee) in zip(split.shares, payees) {
                let role: ReactionBoostSplit.Role = payee.role == "creator" ? .creator : .sender
                #expect(share.role == role, "\(vector.note)")
                #expect(share.userID == (role == .creator ? Self.creator : messageSender), "\(vector.note)")
                #expect(share.cents == (try Self.cents(payee.nativeAmount)), "\(vector.note)")
            }

        default:
            Issue.record("unknown intent \(vector.expected.intent)")
        }
    }

    @Test func minimumFollowsThePayeeCount() {
        #expect(ReactionBoostSplit.minimumCents(payer: Self.member, messageSender: Self.otherMember, creator: Self.creator) == 3)
        #expect(ReactionBoostSplit.minimumCents(payer: Self.member, messageSender: Self.creator, creator: Self.creator) == 1)
        #expect(ReactionBoostSplit.minimumCents(payer: Self.creator, messageSender: Self.member, creator: Self.creator) == 1)
        #expect(ReactionBoostSplit.minimumCents(payer: Self.member, messageSender: Self.member, creator: Self.creator) == nil)
    }

    /// Parses a two-place USD string such as "9.99" to cents without going through `Double`.
    static func cents(_ amount: String) throws -> UInt64 {
        let parts = amount.split(separator: ".")
        let whole = try #require(UInt64(parts[0]))
        let fraction = parts.count > 1 ? try #require(UInt64(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0))) : 0
        return whole * 100 + fraction
    }
}
