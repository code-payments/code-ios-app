import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/collection_funding.json`: how a collection payment is funded from the payer's
/// balances, and the strings the modal and Payment Details draw for it. The canonical copy lives in
/// the orchestrator repo; this one is synced. Never edit it locally.
@Suite struct CollectionFundingVectorTests {

    struct Fixture: Decodable, Sendable {
        let constants: Constants
        let cases: [Case]
        let feeDisplay: [FeeRow]
        let amountDisplay: [AmountRow]
    }

    struct Constants: Decodable, Sendable {
        let minorDigits: Int
    }

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        struct Input: Decodable, Sendable {
            let amountMicros: Int64
            let currency: String
            let minorDigits: Int
            let minTopUpMicros: Int64
            let selected: String?
            let lastPaid: String?
            let balances: [Balance]
        }

        struct Balance: Decodable, Sendable {
            let id: String
            let name: String
            let kind: String
            let fiatMicros: Int64
            let sellFeeBps: Int64
        }

        struct Expected: Decodable, Sendable {
            let selected: String
            let payableWithoutTopUp: Bool
            let shortfallMicros: Int64
            let topUpMicros: Int64
            let totalFeeMicros: Int64
            let legs: [Leg]
        }

        struct Leg: Decodable, Sendable {
            let source: String
            let conversion: Bool
            let soldMicros: Int64
            let feeMicros: Int64
            let deliveredMicros: Int64
            let fromBalanceMicros: Int64?
            let fromTopUpMicros: Int64?
        }

        struct Display: Decodable, Sendable {
            let shortBy: String?
            let addButton: String?
            let topUp: String?
            let modalFee: String?
            let details: Details
        }

        struct Details: Decodable, Sendable {
            let pay: Named
            let use: [UseRow]
            let total: Total
        }

        struct Named: Decodable, Sendable {
            let name: String
            let amount: String
        }

        struct UseRow: Decodable, Sendable {
            let name: String
            let amount: String
            let sublabels: [String]
        }

        struct Total: Decodable, Sendable {
            let label: String
            let amount: String
        }

        let name: String
        let input: Input
        let expected: Expected
        let display: Display

        var testDescription: String { name }
    }

    struct FeeRow: Decodable, Sendable, CustomTestStringConvertible {
        let feeMicros: Int64
        let conversion: Bool
        let kind: String
        let roundedMinor: Int64?
        let modal: String?
        let detailsSublabel: String?

        var testDescription: String { "\(feeMicros) micros, conversion \(conversion)" }
    }

    struct AmountRow: Decodable, Sendable, CustomTestStringConvertible {
        let micros: Int64
        let text: String

        var testDescription: String { "\(micros) micros" }
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "collection_funding", withExtension: "json", subdirectory: "Fixtures")!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(Fixture.self, from: Data(contentsOf: url))
    }()

    /// The id the fixture gives Dollars, held or added by a top-up.
    static let dollars = "dollars"

    /// The fixture's rows are all in USD.
    static let usd = CurrencyCode(rawValue: "usd")!

    // MARK: - Fixture -

    /// Pins the row counts, so a fixture that lost rows can't pass the parameterized tests below
    /// vacuously.
    @Test("Fixture holds every case and display row")
    func fixtureCounts() {
        #expect(Self.fixture.cases.count == 32)
        #expect(Self.fixture.feeDisplay.count == 13)
        #expect(Self.fixture.amountDisplay.count == 7)
        #expect(Set(Self.fixture.cases.map(\.name)).count == Self.fixture.cases.count)
        #expect(Self.fixture.constants.minorDigits == Self.usd.maximumFractionDigits)
        let balances = Self.fixture.cases.flatMap(\.input.balances)
        #expect(balances.allSatisfy { ($0.kind == "dollars") == ($0.id == Self.dollars) })
    }

    // MARK: - Planner -

    @Test("Plan matches every case to the micro", arguments: fixture.cases)
    func plan(_ vector: Case) throws {
        let plan = try Self.plan(vector)
        let expected = vector.expected

        #expect(plan.amountMicros == vector.input.amountMicros)
        #expect(plan.payingCurrency == expected.selected)
        #expect(plan.payableWithoutTopUp == expected.payableWithoutTopUp)
        #expect(plan.shortfallMicros == expected.shortfallMicros)
        #expect(plan.topUpMicros == expected.topUpMicros)
        #expect(plan.totalFeeMicros == expected.totalFeeMicros)
        #expect(plan.legs == expected.legs.map(Self.leg))
    }

    // MARK: - Display -

    @Test("Display matches every case's strings", arguments: fixture.cases)
    func display(_ vector: Case) throws {
        let currency = CurrencyCode(rawValue: vector.input.currency.lowercased())!
        #expect(currency.maximumFractionDigits == vector.input.minorDigits)

        let shown = CollectionFundingDisplay(
            plan: try Self.plan(vector),
            currency: currency,
            dollars: Self.dollars,
            names: Dictionary(uniqueKeysWithValues: vector.input.balances.map { ($0.id, $0.name) })
        )
        let expected = vector.display

        #expect(shown.shortBy == expected.shortBy)
        #expect(shown.addButton == expected.addButton)
        #expect(shown.topUp == expected.topUp)
        #expect(shown.modalFee == expected.modalFee)
        #expect(shown.pay == .init(label: expected.details.pay.name, amount: expected.details.pay.amount))
        #expect(shown.use == expected.details.use.map { .init(label: $0.name, amount: $0.amount, sublabels: $0.sublabels) })
        #expect(shown.total == .init(label: expected.details.total.label, amount: expected.details.total.amount))
    }

    @Test("Fee kind and strings match every fee row", arguments: fixture.feeDisplay)
    func feeDisplay(_ row: FeeRow) {
        let kind = CollectionFundingFeeKind(
            feeMicros: row.feeMicros,
            conversion: row.conversion,
            minorDigits: Self.fixture.constants.minorDigits
        )
        let (name, roundedMinor) = Self.fixtureKind(kind)

        #expect(name == row.kind)
        #expect(roundedMinor == row.roundedMinor)
        #expect(CollectionFundingDisplay.modalFee(feeMicros: row.feeMicros, conversion: row.conversion, currency: Self.usd) == row.modal)
        #expect(CollectionFundingDisplay.feeSublabel(feeMicros: row.feeMicros, conversion: row.conversion, currency: Self.usd) == row.detailsSublabel)
    }

    @Test("Amount text matches every amount row", arguments: fixture.amountDisplay)
    func amountDisplay(_ row: AmountRow) {
        #expect(CollectionFundingDisplay.amountText(micros: row.micros, currency: Self.usd) == row.text)
    }

    // MARK: - Helpers -

    private static func plan(_ vector: Case) throws -> CollectionFundingPlan {
        try planCollectionFunding(
            amountMicros: vector.input.amountMicros,
            minorDigits: vector.input.minorDigits,
            minimumTopUpMicros: vector.input.minTopUpMicros,
            selected: vector.input.selected,
            lastPaid: vector.input.lastPaid,
            dollars: dollars,
            balances: vector.input.balances.map {
                CollectionFundingBalance(id: $0.id, fiatMicros: $0.fiatMicros, sellFeeBps: $0.sellFeeBps)
            }
        )
    }

    private static func leg(_ leg: Case.Leg) -> CollectionFundingPlan.Leg {
        #expect((leg.fromBalanceMicros == nil) == (leg.fromTopUpMicros == nil))
        let split = leg.fromBalanceMicros.flatMap { fromBalance in
            leg.fromTopUpMicros.map { CollectionFundingPlan.DollarsSplit(fromBalanceMicros: fromBalance, fromTopUpMicros: $0) }
        }
        return CollectionFundingPlan.Leg(
            source: leg.source,
            conversion: leg.conversion,
            soldMicros: leg.soldMicros,
            feeMicros: leg.feeMicros,
            deliveredMicros: leg.deliveredMicros,
            dollarsSplit: split
        )
    }

    /// The fixture's name for `kind`, and its rounded minor units where it has them.
    private static func fixtureKind(_ kind: CollectionFundingFeeKind) -> (String, Int64?) {
        switch kind {
        case .none: ("none", nil)
        case .zero: ("zero", nil)
        case .underMinorUnit: ("under_minor", nil)
        case .exact(let minorUnits): ("exact", minorUnits)
        case .approximate(let minorUnits): ("approx", minorUnits)
        }
    }
}
