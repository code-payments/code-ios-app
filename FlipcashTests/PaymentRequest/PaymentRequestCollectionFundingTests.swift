//
//  PaymentRequestCollectionFundingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore
import FlipcashStore
@testable import Flipcash

@MainActor
@Suite("PaymentRequestPayment funding a collection")
struct PaymentRequestCollectionFundingTests {

    private let requestID = PaymentRequestID(data: Data([6]))
    private let chat = ConversationID(data: Data(repeating: 0x0E, count: 32))
    private let intentID = Data(repeating: 8, count: 32)
    private static let jeffyMint = MintMetadata.makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000)

    @MainActor
    private final class Server {
        var intentResult: Result<Data, ErrorGetPaymentIntentID>
        var isPaid = false
        var intentReads = 0

        init(intentResult: Result<Data, ErrorGetPaymentIntentID>) {
            self.intentResult = intentResult
        }
    }

    /// Swaps that never touch a network; a refresh writes `balancesAfterRefresh` to the database
    /// and waits for the session to read them back.
    @MainActor
    private final class FakeSwapper: CollectionSwapping {
        var submitted: [(swap: CollectionFundingSwap, id: SwapId)] = []
        var waitResult: SwapState = .finalized
        var balancesAfterRefresh: [PublicKey: UInt64] = [:]
        var refreshes = 0
        weak var container: SessionContainer?

        func submit(_ swap: CollectionFundingSwap, swapID: SwapId) async throws {
            submitted.append((swap, swapID))
        }

        func state(of swapID: SwapId) async throws -> SwapState? { nil }

        func waitForTerminalState(of swapID: SwapId) async throws -> SwapState { waitResult }

        func refreshBalances() async throws {
            refreshes += 1
            guard let container else { return }
            try await PaymentRequestCollectionFundingTests.write(balancesAfterRefresh, to: container)
        }
    }

    /// Top-ups that never reach Coinbase. An order that lands adds `delivered` USD to the Dollars
    /// balance the first time it is waited on.
    @MainActor
    private final class FakeTopUpper: CollectionTopUpping {
        var orders: [(amountUSD: Decimal, orderRef: String)] = []
        var orderResult: CollectionTopUpOrder = .charged
        /// What the order adds to the Dollars balance; nil adds nothing.
        var delivered: Decimal?
        /// Runs inside `order`, once Apple Pay has authorized and before the order returns.
        var whileOrdering: (() -> Void)?
        var waits = 0
        /// Cancels the waiting task inside `awaitDollars`, after any delivery, as the sheet closing does.
        var cancelsWait = false
        /// Holds `awaitDollars` until `releaseWait` runs.
        var holdsWait = false
        var releaseWait: (() -> Void)?
        weak var container: SessionContainer?

        func makeOrderRef() -> String { "order-\(orders.count + 1)" }

        func dollarsBalance() async throws -> Decimal {
            container?.session.balance(for: .usdf)?.usdf.value ?? 0
        }

        func order(amountUSD: Decimal, orderRef: String, onAuthorized: @escaping () -> Void) async -> CollectionTopUpOrder {
            orders.append((amountUSD, orderRef))
            if case .notCharged = orderResult {} else { onAuthorized() }
            whileOrdering?()
            return orderResult
        }

        func awaitDollars(reaching targetUSD: Decimal) async -> Bool {
            waits += 1
            if holdsWait {
                await withCheckedContinuation { continuation in releaseWait = { continuation.resume() } }
            }
            if let delivered, let container {
                self.delivered = nil
                let held = container.session.balance(for: .usdf)?.quarks ?? 0
                let added = NSDecimalNumber(decimal: delivered * 1_000_000).uint64Value
                try? await PaymentRequestCollectionFundingTests.write([.usdf: held + added], to: container)
            }
            if cancelsWait { withUnsafeCurrentTask { $0?.cancel() } }
            return ((try? await dollarsBalance()) ?? 0) >= targetUSD
        }
    }

    /// Writes `balances` to the database and waits for the session to read them back.
    fileprivate static func write(_ balances: [PublicKey: UInt64], to container: SessionContainer) async throws {
        try container.database.transaction { db in
            for (mint, quarks) in balances {
                try db.insertBalance(quarks: quarks, mint: mint, costBasis: 0, date: .now)
            }
        }
        for _ in 0..<500 where !balances.allSatisfy({ container.session.balance(for: $0.key)?.quarks == $0.value }) {
            await Task.yield()
        }
    }

    private func collection(amount: Double) -> GroupPaymentRequest {
        GroupPaymentRequest(
            id: requestID,
            creator: UUID(),
            createdAt: .now.addingTimeInterval(-60),
            status: .open,
            closedAt: nil,
            version: 1,
            chatID: chat,
            split: nil,
            collection: .init(text: nil, currency: "usd", endsAt: nil, paymentAmount: .fixed(.init(nativeAmount: amount))),
            payerSummary: .init(payerCount: 0, paidCount: 0, nativeAmountDue: 0, nativeAmountPaid: 0)
        )
    }

    private func store(_ server: Server, amount: Double, viewer: UserID) -> PaymentRequests {
        let request = collection(amount: amount)
        return PaymentRequests(
            getChatPage: { _, _, _ in [] },
            getRequest: { _ in
                let caller = server.isPaid
                    ? GroupPaymentRequest.Payer(userID: viewer, nativeAmountDue: 0, nativeAmountPaid: amount, status: .paid(paidAt: .now, settlement: .intent(Data(repeating: 9, count: 32))))
                    : nil
                return (request, nil, caller)
            },
            getPaymentIntentID: { _ in
                server.intentReads += 1
                return try server.intentResult.get()
            },
            getPaidPayers: { _, _ in ([], 1) },
            showsCollections: { true }
        )
    }

    private struct Fixture {
        let payment: PaymentRequestPayment
        let payer: FakeRequestPayer
        let swapper: FakeSwapper
        let topUpper: FakeTopUpper
        let fundingStore: CollectionFundingStore
        let container: SessionContainer
        let amount: Double
    }

    /// A $`amount` collection payment over a wallet holding `dollars` USDF quarks and `jeffy`
    /// Jeffy quarks.
    private func fixture(
        _ server: Server,
        amount: Double,
        dollars: UInt64?,
        jeffy: UInt64?,
        lastPaid: PublicKey? = nil,
        storesJeffyMetadata: Bool = false,
        fundsCollections: Bool = true,
        sendLimit: Decimal = 1000,
        clock: @escaping () -> Date = Date.init
    ) async throws -> Fixture {
        var holdings: [SessionContainer.Holding] = []
        if let dollars {
            holdings.append(SessionContainer.Holding(mint: .usdf, quarks: dollars))
        }
        if let jeffy {
            holdings.append(SessionContainer.Holding(mint: Self.jeffyMint, quarks: jeffy))
        }
        let limit = FiatAmount(value: sendLimit, currency: .usd)
        let container = try SessionContainer.makeTest(
            holdings: holdings,
            mints: (dollars == nil ? [.usdf] : []) + (storesJeffyMetadata && jeffy == nil ? [Self.jeffyMint] : []),
            limits: Limits(
                sinceDate: .now,
                fetchDate: .now,
                sendLimits: [.usd: SendLimit(nextTransaction: limit, maxPerTransaction: limit, maxPerDay: limit)]
            )
        )
        container.ratesController.configureTestRates(balanceCurrency: .usd, rates: [Rate(fx: 1.0, currency: .usd)])
        await container.ratesController.verifiedProtoService.saveRates([.freshRate(currencyCode: "USD", rate: 1.0)])
        container.ratesController.selectToken(.usdf, source: .user)

        let requests = store(server, amount: amount, viewer: container.session.userID)
        try await requests.refreshDetails(requestID)
        let payer = FakeRequestPayer()
        let swapper = FakeSwapper()
        swapper.container = container
        let fundingStore = CollectionFundingStore(
            userID: container.session.userID,
            defaults: UserDefaults(suiteName: "PaymentRequestCollectionFundingTests.\(UUID().uuidString)")!
        )
        if let lastPaid {
            fundingStore.recordPaid(currency: lastPaid.base58)
        }
        let topUpper = FakeTopUpper()
        topUpper.container = container
        let payment = PaymentRequestPayment(
            requestID: requestID,
            sessionContainer: container,
            requests: requests,
            payer: payer,
            resolver: payer,
            swapper: swapper,
            topUpper: topUpper,
            fundingStore: fundingStore,
            fundsCollections: { fundsCollections },
            clock: clock
        )
        return Fixture(
            payment: payment, payer: payer, swapper: swapper, topUpper: topUpper,
            fundingStore: fundingStore, container: container, amount: amount
        )
    }

    /// `f` as a relaunch finds it: a new payment over the same wallet and funding store, with a
    /// top-up client that has ordered nothing in this process.
    private func relaunch(_ f: Fixture, _ server: Server, clock: @escaping () -> Date = Date.init) async throws -> Fixture {
        let requests = store(server, amount: f.amount, viewer: f.container.session.userID)
        try await requests.refreshDetails(requestID)
        let topUpper = FakeTopUpper()
        topUpper.container = f.container
        let payment = PaymentRequestPayment(
            requestID: requestID,
            sessionContainer: f.container,
            requests: requests,
            payer: f.payer,
            resolver: f.payer,
            swapper: f.swapper,
            topUpper: topUpper,
            fundingStore: f.fundingStore,
            fundsCollections: { true },
            clock: clock
        )
        return Fixture(
            payment: payment, payer: f.payer, swapper: f.swapper, topUpper: topUpper,
            fundingStore: f.fundingStore, container: f.container, amount: f.amount
        )
    }

    /// 2,000 Jeffy, worth over $20 on the test curve.
    private static let plentyOfJeffy: UInt64 = 20_000_000_000_000

    // MARK: - Paying currency

    @Test("The first collection payment opens on Dollars")
    func firstPaymentDefaultsToDollars() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: Self.plentyOfJeffy)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.usdf.base58)
        #expect(f.payment.payingBalance?.stored.mint == .usdf)
    }

    @Test("A later collection payment opens on the last paid currency")
    func laterPaymentDefaultsToLastPaid() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: Self.plentyOfJeffy, lastPaid: .jeffy)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.jeffy.base58)
        #expect(f.payment.payingBalance?.stored.mint == .jeffy)
    }

    @Test("The last paid currency is shown and offered even at a zero balance")
    func lastPaidAtZero() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: 0, lastPaid: .jeffy)

        let plan = try #require(f.payment.fundingPlan)
        #expect(plan.payingCurrency == PublicKey.jeffy.base58)
        #expect(plan.legs.contains { $0.source == PublicKey.usdf.base58 && $0.conversion })
        #expect(f.payment.payingBalance?.stored.mint == .jeffy)
        #expect(f.payment.paymentOptions.first?.stored.mint == .jeffy)
    }

    @Test("A last paid currency the app has no record of falls back to Dollars")
    func lastPaidNotHeld() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: nil, lastPaid: .jeffy)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.usdf.base58)
    }

    @Test("A last paid currency with no balance row but stored metadata opens at zero")
    func lastPaidNoRowWithMetadata() async throws {
        let f = try await fixture(
            Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: nil,
            lastPaid: .jeffy, storesJeffyMetadata: true
        )
        try #require(f.container.session.balance(for: .jeffy) == nil)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.jeffy.base58)
        #expect(f.payment.payingBalance?.stored.mint == .jeffy)
        #expect(f.payment.payingBalance?.stored.quarks == 0)
    }

    @Test("Changing currency reruns the plan and starts no swap")
    func pickRerunsPlan() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: 0)
        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.usdf.base58)
        let stored = try #require(f.container.session.balance(for: .jeffy))
        let jeffy = ExchangedBalance(stored: stored, exchangedFiat: stored.computeExchangedValue(with: Rate(fx: 1, currency: .usd)))

        f.payment.selectCurrencyAction(exchangedBalance: jeffy)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.jeffy.base58)
        #expect(f.payment.fundingPlan?.legs.contains { $0.source == PublicKey.usdf.base58 && $0.conversion } == true)
        // The pill and Payment Details follow the pick: Dollars buy Jeffy at no fee.
        #expect(f.payment.payingBalance?.stored.mint == .jeffy)
        #expect(f.payment.fundingSheet?.payingCurrency == PublicKey.jeffy.base58)
        #expect(f.payment.fundingSheet?.feeLine == "no conversion fees")
        #expect(f.payment.fundingSheet?.use.map(\.currency) == [PublicKey.usdf.base58])
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.swapper.refreshes == 0)
        #expect(f.container.ratesController.selectedTokenMint == .usdf)
        #expect(f.fundingStore.lastPaidCurrency == nil)
    }

    // MARK: - Submit

    @Test("A payment conversions cover converts first, then pays once in the paying currency")
    func convertsThenPays() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.payableWithoutTopUp)
        try #require(plan.legs.contains { $0.source == PublicKey.jeffy.base58 && $0.conversion })
        let sheet = try #require(f.payment.fundingSheet)
        #expect(sheet.feeLine?.hasPrefix("plus ~$") == true)
        #expect(sheet.use.map(\.currency) == [PublicKey.usdf.base58, PublicKey.jeffy.base58])
        f.swapper.balancesAfterRefresh = [.usdf: 10_500_000]

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .success)

        #expect(f.swapper.submitted.count == 1)
        #expect(f.swapper.submitted.first?.swap.source == .jeffy)
        #expect(f.swapper.submitted.first?.swap.destination == .usdf)
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.nativeAmount == FiatAmount(value: 10, currency: .usd))
        #expect(f.payer.payments.first?.amount.mint == .usdf)
        #expect(f.fundingStore.lastPaidCurrency == PublicKey.usdf.base58)
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58) == nil)
    }

    @Test("With no Dollars account listed yet, the pill still says Dollars and Jeffy funds the payment")
    func noDollarsRow() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: Self.plentyOfJeffy)
        try #require(f.container.session.balance(for: .usdf) == nil)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.payableWithoutTopUp)
        #expect(plan.payingCurrency == PublicKey.usdf.base58)
        #expect(f.payment.payingBalance?.stored.mint == .usdf)
        #expect(f.payment.payingBalance?.stored.quarks == 0)
        f.swapper.balancesAfterRefresh = [.usdf: 10_500_000]

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .success)

        #expect(f.swapper.submitted.first?.swap.source == .jeffy)
        #expect(f.swapper.submitted.first?.swap.destination == .usdf)
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.mint == .usdf)
    }

    @Test("With no Dollars row, the picker still offers Dollars after another currency is picked")
    func noDollarsRowPickerKeepsDollars() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: Self.plentyOfJeffy)
        let stored = try #require(f.container.session.balance(for: .jeffy))
        let jeffy = ExchangedBalance(stored: stored, exchangedFiat: stored.computeExchangedValue(with: Rate(fx: 1, currency: .usd)))

        f.payment.selectCurrencyAction(exchangedBalance: jeffy)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.jeffy.base58)
        let mints = f.payment.paymentOptions.map(\.stored.mint)
        #expect(mints.contains(.usdf))
        #expect(mints.filter { $0 == .jeffy }.count == 1)
    }

    @Test("A paying currency that covers the amount pays with no swap")
    func paysWithoutConverting() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: Self.plentyOfJeffy)

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .success)

        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.count == 1)
    }

    @Test("A payment that fails records no last paid currency")
    func failedPaymentKeepsLastPaid() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: nil)
        f.payer.failure = ErrorGetPaymentIntentID.unknown

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .failed)

        #expect(f.fundingStore.lastPaidCurrency == nil)
    }

    @Test("A retry after an unsettled swap reads the intent ID first and stops on ALREADY_PAID")
    func retryStopsOnAlreadyPaid() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        f.swapper.waitResult = .submitting

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .failed)
        let kept = try #require(f.swapper.submitted.first?.id)
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58) == kept)
        #expect(f.container.session.dialogItem?.title == "Conversion Pending")

        // The swap and the payment landed after all.
        server.intentResult = .failure(.alreadyPaid)
        server.isPaid = true

        #expect(await f.payment.submit() == .success)
        #expect(server.intentReads == 2)
        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.isEmpty)
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58) == nil)
    }

    @Test("A shortfall conversions can't cover returns the short state and converts or orders nothing")
    func uncoverableShowsShort() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 3_000_000, jeffy: nil)

        #expect(f.payment.fundingPlan?.payableWithoutTopUp == false)
        #expect(f.payment.fundingPlan?.topUpMicros == 7_000_000)
        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .short)

        #expect(f.swapper.submitted.isEmpty)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem == nil)
    }

    // MARK: - Adding money (S5)

    @Test("1.1: a collection at a zero balance opens the sheet on the short state, not No Balance Yet")
    func zeroBalanceOpensSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        let flow = PaymentRequestPayFlow()

        let result = await flow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment)

        #expect(result == .ready)
        #expect(flow.isPaying)
        #expect(f.container.session.dialogItem == nil)
        #expect(f.payment.fundingPlan?.topUpMicros == 10_000_000)
    }

    @Test("A top-up adds the drawn amount, then pays once when the Dollars land, with no second confirmation")
    func topUpThenPayOnce() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.delivered = 5
        var recordWhileOrdering: CollectionFundingStore.PendingTopUp?
        f.topUpper.whileOrdering = { recordWhileOrdering = f.fundingStore.pendingTopUp(for: requestID) }

        #expect(await f.payment.prepare() == .ready)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .success)

        #expect(f.topUpper.orders.map(\.amountUSD) == [5])
        // Persisted before Apple Pay returned, with the Dollars it started from.
        let record = try #require(recordWhileOrdering)
        #expect(record.orderRef == "order-1")
        #expect(record.amountUSD == 5)
        #expect(record.baselineUSD == 6)
        #expect(record.authorized)
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.nativeAmount.value == 10)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.swapper.submitted.isEmpty)
    }

    @Test("An exact-cents top-up orders the exact cents the button showed", arguments: [
        (amount: 10.0, micros: Int64(10_000_000), usd: Decimal(10)),
        (amount: 12.04, micros: Int64(12_040_000), usd: Decimal(string: "12.04")!),
    ])
    func exactCentsOrder(_ c: (amount: Double, micros: Int64, usd: Decimal)) async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: c.amount, dollars: nil, jeffy: nil)
        f.topUpper.delivered = c.usd

        #expect(await f.payment.prepare() == .ready)
        #expect(f.payment.fundingPlan?.topUpMicros == c.micros)
        #expect(await f.payment.addAndPay(topUpMicros: c.micros) == .success)

        #expect(f.topUpper.orders.map(\.amountUSD) == [c.usd])
        #expect(f.payer.payments.count == 1)
    }

    @Test("A top-up the balances no longer match orders nothing and returns the short state")
    func replanDiffersOrdersNothing() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 3_000_000, jeffy: nil)

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .short)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("A top-up for a payment over the send limit opens no Apple Pay and orders nothing")
    func overSendLimitOrdersNothing() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil, sendLimit: 8)

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem?.title == "Transaction Limit Reached")
    }

    @Test("A wait the closing sheet cuts short keeps the record, shows nothing and pays nothing", arguments: [true, false])
    func cancelledWaitDecidesNothing(authorized: Bool) async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        let record = CollectionFundingStore.PendingTopUp(
            orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: .now, authorized: authorized
        )
        f.fundingStore.setPendingTopUp(record, for: requestID)
        f.topUpper.cancelsWait = true

        #expect(await f.payment.prepare() == .ready)
        let outcome = await Task { await f.payment.resumePendingTopUp() }.value

        #expect(outcome == .failed)
        #expect(f.topUpper.waits == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == record)
        #expect(f.container.session.dialogItem == nil)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("Dollars landing as the sheet closes clear the record and stay; the next attempt pays from them")
    func cancelledAsDollarsLand() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: .now, authorized: true),
            for: requestID
        )
        f.topUpper.delivered = 5
        f.topUpper.cancelsWait = true

        #expect(await f.payment.prepare() == .ready)
        #expect(await Task { await f.payment.resumePendingTopUp() }.value == .failed)
        #expect(f.payer.payments.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.container.session.balance(for: .usdf)?.quarks == 11_000_000)

        #expect(await f.payment.submit() == .success)
        #expect(f.payer.payments.count == 1)
        #expect(f.topUpper.orders.isEmpty)
    }

    @Test("A cancelled Apple Pay charges nothing, clears its record and pays nothing")
    func cancelledTopUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.orderResult = .notCharged(.cancelled)

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("Killed between Apple Pay and pay: the relaunch waits on the pending top-up, pays once and orders nothing")
    func relaunchWaitsOnPendingTopUp() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: 6_000_000, jeffy: nil)
        // Apple Pay authorized, then the process went away before the Dollars landed: the
        // order's outcome is unknown and nothing was paid.
        f.topUpper.orderResult = .mayDeliver

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)
        #expect(f.payer.payments.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID)?.authorized == true)

        let relaunched = try await relaunch(f, server)
        relaunched.topUpper.delivered = 5
        #expect(await relaunched.payment.prepare() == .ready)
        #expect(relaunched.payment.hasPendingTopUp)
        #expect(await relaunched.payment.resumePendingTopUp() == .success)

        #expect(relaunched.topUpper.orders.isEmpty)
        #expect(f.topUpper.orders.count == 1)
        #expect(f.payer.payments.count == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("A second tap while a top-up is pending waits on it and never orders again")
    func secondTapWaitsOnPending() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.orderResult = .mayDeliver

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)
        #expect(f.container.session.dialogItem?.title == "Top-Up Pending")

        f.topUpper.delivered = 5
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .success)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.payer.payments.count == 1)
    }

    @Test("An Apple Pay never authorized and older than the settlement window clears on relaunch and orders nothing")
    func staleUnauthorizedRecordClears() async throws {
        let server = Server(intentResult: .success(intentID))
        let placed = Date(timeIntervalSince1970: 1_000_000)
        let f = try await fixture(server, amount: 10, dollars: 6_000_000, jeffy: nil)
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: placed, authorized: false),
            for: requestID
        )

        let relaunched = try await relaunch(f, server, clock: { placed.addingTimeInterval(3_600) })
        #expect(await relaunched.payment.prepare() == .ready)
        #expect(await relaunched.payment.resumePendingTopUp() == nil)

        #expect(relaunched.topUpper.waits == 0)
        #expect(relaunched.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("A cleared top-up that charged nothing pays nothing on open, even when other balances now cover it")
    func clearedUnauthorizedPaysNothing() async throws {
        let server = Server(intentResult: .success(intentID))
        let placed = Date(timeIntervalSince1970: 1_000_000)
        let f = try await fixture(server, amount: 10, dollars: 6_000_000, jeffy: Self.plentyOfJeffy)
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: placed, authorized: false),
            for: requestID
        )

        let relaunched = try await relaunch(f, server, clock: { placed.addingTimeInterval(3_600) })
        #expect(await relaunched.payment.prepare() == .ready)
        #expect(await relaunched.payment.resumePendingTopUp() == nil)

        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.isEmpty)
        #expect(relaunched.topUpper.orders.isEmpty)
    }

    @Test("A sheet reopened while the first one's top-up is still running joins it and pays once")
    func overlappingRunsPayOnce() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: .now, authorized: true),
            for: requestID
        )
        f.topUpper.delivered = 5
        f.topUpper.holdsWait = true

        #expect(await f.payment.prepare() == .ready)
        let first = Task { await f.payment.addAndPay(topUpMicros: 5_000_000) }
        while f.topUpper.releaseWait == nil { await Task.yield() }
        let second = Task { await f.payment.resumePendingTopUp() }
        for _ in 0..<10 { await Task.yield() }
        f.topUpper.releaseWait?()

        #expect(await first.value == .success)
        #expect(await second.value == .success)
        #expect(f.topUpper.waits == 1)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.count == 1)
    }

    @Test("A payment that fails after the top-up keeps the Dollars, and the retry charges nothing")
    func failureAfterTopUpKeepsDollars() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.delivered = 5
        f.payer.failure = URLError(.timedOut)

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)
        #expect(f.container.session.balance(for: .usdf)?.quarks == 11_000_000)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)

        f.payer.failure = nil
        #expect(f.payment.fundingPlan?.topUpMicros == 0)
        #expect(await f.payment.submit() == .success)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.payer.payments.count == 2)
        #expect(server.intentReads == 2)
    }

    @Test("A short delivery replans from the balance seen and asks before any further top-up")
    func shortDeliveryAsksAgain() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 12, dollars: nil, jeffy: nil)
        // 98.3% of the $12 order: counted as landed, but $0.20 short of the payment.
        f.topUpper.delivered = Decimal(string: "11.80")!

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 12_000_000) == .short)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(f.payment.fundingPlan?.shortfallMicros == 200_000)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)
    }

    @Test("With Group Money off a collection neither plans nor converts")
    func flagOff() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy, fundsCollections: false)

        #expect(f.payment.fundingPlan == nil)
        #expect(f.payment.fundingSheet == nil)
        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .failed)
        #expect(f.swapper.submitted.isEmpty)
    }
}
