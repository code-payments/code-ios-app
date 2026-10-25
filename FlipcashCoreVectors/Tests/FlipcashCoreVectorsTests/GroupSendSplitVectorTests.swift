import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/group-send-split.json`: each recipient's part of a group send, in selection order.
/// The canonical copy lives in the orchestrator repo; this one is synced. Never edit it locally.
@Suite struct GroupSendSplitVectorTests {

    struct Fixture: Decodable, Sendable {
        let maxRecipients: Int
        let minimumPart: String
        let vectors: [Vector]
    }

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let total: String
        let recipients: Int
        let intent: String?
        let parts: [String]?
        let eachLabel: String?
        let expectedError: String?

        var testDescription: String { name }
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "group-send-split", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    @Test func constantsMatchTheCrossPlatformVectors() {
        #expect(Self.fixture.maxRecipients == GroupSendSplit.maxRecipients)
        #expect(Self.usd(Self.fixture.minimumPart) == GroupSendSplit.minimumPartUnits)
    }

    @Test(arguments: fixture.vectors)
    func splitMatchesTheCrossPlatformVectors(vector: Vector) throws {
        let total = FiatAmount(value: try #require(Decimal(string: vector.total)), currency: .usd)
        let result = Result { () throws(GroupSendSplit.Rejection) in
            try GroupSendSplit.split(total: total, recipients: vector.recipients)
        }

        if let expectedError = vector.expectedError {
            let expected: GroupSendSplit.Rejection = switch expectedError {
            case "no-recipients": .noRecipients
            case "too-many-recipients": .tooManyRecipients
            case "part-below-minimum": .partBelowMinimum
            default: fatalError("unknown error \(expectedError)")
            }
            #expect(throws: expected) { try result.get() }
            return
        }

        let split = try result.get()
        let parts = try #require(vector.parts)
        #expect(split.parts == parts.map(Self.usd))
        #expect(split.parts.reduce(0, +) == Self.usd(vector.total))
        #expect(split.amounts(in: .usd).map { $0.formatted(minimumFractionDigits: 2) } == parts.map { "$\($0)" })
        #expect((split.parts.count > 1 ? "SendPublicMultiPayment" : "SendPublicPayment") == vector.intent)
        if let eachLabel = vector.eachLabel {
            #expect(split.eachLabel(in: .usd) == eachLabel)
        }
    }

    @Test func everyVectorIsRun() {
        #expect(Self.fixture.vectors.count == 14)
        #expect(Self.fixture.vectors.filter { $0.expectedError != nil }.count == 4)
    }

    @Test func zeroDecimalCurrencySplitsInWholeUnits() throws {
        let split = try GroupSendSplit.split(total: FiatAmount(value: 1000, currency: .jpy), recipients: 3)
        #expect(split.parts == [334, 333, 333])
        #expect(split.amounts(in: .jpy).map(\.value) == [334, 333, 333])
    }

    /// Parses a two-place USD string such as "9.99" to cents without going through `Double`.
    static func usd(_ amount: String) -> UInt64 {
        let parts = amount.split(separator: ".")
        let whole = UInt64(parts[0])!
        let fraction = parts.count > 1 ? UInt64(parts[1].padding(toLength: 2, withPad: "0", startingAt: 0))! : 0
        return whole * 100 + fraction
    }
}
