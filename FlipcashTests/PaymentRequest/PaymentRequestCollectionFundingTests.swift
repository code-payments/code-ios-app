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

    /// Swaps that never touch a network; a refresh stores `balancesAfterRefresh` through the step
    /// `Session.fetchBalance()` uses, and doesn't wait for the session to read them back.
    @MainActor
    private final class FakeSwapper: CollectionSwapping {
        var submitted: [(swap: CollectionFundingSwap, id: SwapId)] = []
        var waitResult: SwapState = .finalized
        var balancesAfterRefresh: [PublicKey: UInt64] = [:]
        /// Replaces `balancesAfterRefresh` when a swap starts, so the refresh after it reads what
        /// that swap delivered.
        var balancesAfterStart: [PublicKey: UInt64]?
        /// What the server says of each swap; one not listed was never seen.
        var states: [SwapId: SwapState] = [:]
        /// Runs inside `waitForTerminalState` before it answers. The wait runs in its own task under
        /// a deadline, so closing the sheet means cancelling the run from here.
        var whileWaiting: (() -> Void)?
        /// Cancels the run inside `refreshBalances`, after the balances are written, as the sheet
        /// closing just as a swap lands does.
        var cancelsAtRefresh = false
        /// Thrown by `waitForTerminalState` in place of `waitResult`, as a poll cut short throws.
        var waitError: (any Error)?
        var refreshes = 0
        weak var container: SessionContainer?

        /// Starts refused after this many, as the server refuses a swap whose source the earlier
        /// ones drained ("insufficient balance").
        var refusesStartsAfter: Int?
        var refusedStarts = 0
        struct InsufficientBalance: Error {}

        /// Refreshes after a swap starts that read `balancesWhileLagging` before `balancesAfterStart`
        /// shows: the source debited and the destination not yet credited, as the server answers
        /// for a moment after a swap finalizes.
        var lagsRefreshes = 0
        var balancesWhileLagging: [PublicKey: UInt64]?
        private var lagLeft = 0

        func start(_ swap: CollectionFundingSwap, swapID: SwapId, fundingIntentID: PublicKey) async throws {
            if let refusesStartsAfter, submitted.count >= refusesStartsAfter {
                refusedStarts += 1
                throw InsufficientBalance()
            }
            submitted.append((swap, swapID))
            if let balancesAfterStart { balancesAfterRefresh = balancesAfterStart }
            lagLeft = lagsRefreshes
        }

        /// What GetPendingSwaps lists.
        var pending: [PendingCollectionSwap] = []
        /// Each swap funded under the id GetPendingSwaps recorded for it, in order.
        var funded: [SwapId] = []
        /// Replaces `balancesAfterRefresh` when a swap is funded, so the refresh after it reads what
        /// that swap delivered.
        var balancesAfterFund: [PublicKey: UInt64]?

        func pendingSwaps() async throws -> [PendingCollectionSwap] { pending }

        /// Thrown by `fund` before anything is funded, as the server refusing the funding intent does.
        var fundError: (any Error)?

        func fund(_ pending: PendingCollectionSwap, fundingIntentID: PublicKey, currency: CurrencyCode) async throws {
            if let fundError { throw fundError }
            funded.append(pending.swapID)
            states[pending.swapID] = .funding
            if let balancesAfterFund { balancesAfterRefresh = balancesAfterFund }
        }

        func state(of swapID: SwapId) async throws -> SwapState? { states[swapID] }

        func waitForTerminalState(of swapID: SwapId) async throws -> SwapState {
            whileWaiting?()
            if let waitError { throw waitError }
            // A swap whose funding never landed doesn't move.
            if states[swapID] == .created { return .created }
            return waitResult
        }

        func refreshBalances() async throws {
            refreshes += 1
            defer { if cancelsAtRefresh { withUnsafeCurrentTask { $0?.cancel() } } }
            guard let container else { return }
            var balances = balancesAfterRefresh
            if lagLeft > 0, let balancesWhileLagging {
                lagLeft -= 1
                balances = balancesWhileLagging
            }
            try PaymentRequestCollectionFundingTests.store(balances, in: container)
        }

        func balanceQuarks(of mint: PublicKey) -> UInt64 {
            container?.session.balance(for: mint)?.quarks ?? 0
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
        /// Coinbase's id for the order, passed on as Apple Pay authorizes it.
        var coinbaseOrderID: String?
        /// What each read of an order back from Coinbase answers, in turn; false once spent.
        var orderFailedResults: [Bool] = []
        var lookups: [String] = []
        weak var container: SessionContainer?

        func makeOrderRef() -> String { "order-\(orders.count + 1)" }

        func orderFailed(orderID: String) async -> Bool {
            lookups.append(orderID)
            return orderFailedResults.isEmpty ? false : orderFailedResults.removeFirst()
        }

        func dollarsBalance() async throws -> Decimal {
            container?.session.balance(for: .usdf)?.usdf.value ?? 0
        }

        func order(amountUSD: Decimal, orderRef: String, onAuthorized: @escaping (String?) -> Void) async -> CollectionTopUpOrder {
            orders.append((amountUSD, orderRef))
            if case .notCharged = orderResult {} else { onAuthorized(coinbaseOrderID) }
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
                try? PaymentRequestCollectionFundingTests.store([.usdf: held + added], in: container)
            }
            if cancelsWait { withUnsafeCurrentTask { $0?.cancel() } }
            return ((try? await dollarsBalance()) ?? 0) >= targetUSD
        }
    }

    /// Stores `balances` through the step a balance fetch stores what it read with.
    fileprivate static func store(_ balances: [PublicKey: UInt64], in container: SessionContainer) throws {
        let accounts = try balances.map { mint, quarks in
            var proto = Ocp_Account_V1_TokenAccountInfo()
            proto.address = mint.solanaAccountID
            proto.mint = mint.solanaAccountID
            proto.owner = mint.solanaAccountID
            proto.authority = mint.solanaAccountID
            proto.balance = quarks
            return try AccountInfo(proto)
        }
        container.session.storeBalances(accounts, at: .now)
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
        let defaults: UserDefaults
        let requests: PaymentRequests
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
        submissionTimeout: Duration = PaymentRequestPayment.submissionTimeout,
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
        let defaults = UserDefaults(suiteName: "PaymentRequestCollectionFundingTests.\(UUID().uuidString)")!
        let fundingStore = CollectionFundingStore(userID: container.session.userID, defaults: defaults)
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
            submissionTimeout: submissionTimeout,
            deliveryInterval: .zero,
            clock: clock
        )
        return Fixture(
            payment: payment, payer: payer, swapper: swapper, topUpper: topUpper,
            fundingStore: fundingStore, container: container, amount: amount, defaults: defaults,
            requests: requests
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
            deliveryInterval: .zero,
            clock: clock
        )
        return Fixture(
            payment: payment, payer: f.payer, swapper: f.swapper, topUpper: topUpper,
            fundingStore: f.fundingStore, container: f.container, amount: f.amount, defaults: f.defaults,
            requests: requests
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

    // MARK: - Payment Details

    /// The page the pay sheet shows once its ⓘ sets `wantsDetails`, read from this payment.
    private func page(_ f: Fixture, wantsDetails: Bool) -> CollectionPaySheetPage {
        CollectionPaySheetPage(wantsDetails: wantsDetails, isFinishing: f.payment.isFinishing, content: f.payment.fundingSheet)
    }

    @Test("5.2 to 5.3: the fee line's ⓘ pushes Payment Details over the pay content, for the plan the pay content shows")
    func feeLineOpensDetails() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        let sheet = try #require(f.payment.fundingSheet)
        try #require(sheet.detailsEntries == [.feeLine])

        #expect(page(f, wantsDetails: false) == .pay)
        #expect(page(f, wantsDetails: true) == .details)
        #expect(page(f, wantsDetails: true).pagerProgress == 1)
        #expect(sheet.use.map(\.currency) == [PublicKey.usdf.base58, PublicKey.jeffy.base58])
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("Back from Payment Details returns to the pay content with the picked currency and its plan as they were")
    func backKeepsPick() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: 0)
        let stored = try #require(f.container.session.balance(for: .jeffy))
        f.payment.selectCurrencyAction(exchangedBalance: ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: Rate(fx: 1, currency: .usd))
        ))
        let picked = try #require(f.payment.fundingSheet)
        try #require(picked.payingCurrency == PublicKey.jeffy.base58)
        try #require(picked.detailsEntries == [.feeLine])

        #expect(page(f, wantsDetails: true) == .details)
        #expect(page(f, wantsDetails: false) == .pay)
        #expect(page(f, wantsDetails: false).pagerProgress == 0)

        #expect(f.payment.payingBalance?.stored.mint == .jeffy)
        #expect(f.payment.fundingSheet == picked)
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.isEmpty)
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
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58, destination: PublicKey.usdf.base58) == nil)
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

    @Test("The pill keeps the currency paid in once the request reads paid, until the sheet closes")
    func pillKeepsPaidCurrency() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: 100_000_000, jeffy: Self.plentyOfJeffy, lastPaid: .jeffy)
        await priceJeffy(f)
        try #require(f.payment.payingBalance?.stored.mint == .jeffy)

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .success)
        server.isPaid = true
        try await f.requests.refreshDetails(requestID)

        // The plan ends with nothing left to pay; the success hold still draws the pill.
        #expect(f.payment.payable == nil)
        #expect(f.payment.payingBalance?.stored.mint == .jeffy)
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
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58, destination: PublicKey.usdf.base58) == kept)
        #expect(f.container.session.dialogItem?.title == "Conversion Pending")
        #expect(f.container.session.dialogItem?.subtitle == "Your conversion is still pending. Try again shortly.")

        // The swap and the payment landed after all.
        server.intentResult = .failure(.alreadyPaid)
        server.isPaid = true

        #expect(await f.payment.submit() == .success)
        #expect(server.intentReads == 2)
        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.isEmpty)
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58, destination: PublicKey.usdf.base58) == nil)
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

    @Test("1.1: a collection at a zero balance opens neither the sheet nor No Balance Yet, and orders nothing")
    func zeroBalanceOpensNoSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        let flow = PaymentRequestPayFlow()

        let result = await flow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment)

        #expect(result == .fundedByTopUp)
        #expect(!flow.isPaying)
        #expect(f.container.session.dialogItem == nil)
        #expect(f.payment.fundingPlan?.topUpMicros == 10_000_000)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
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

    // MARK: - Keeping the paying currency through a top-up

    /// About $1.50 of Jeffy on the test curve, as the device case held in its picked currency.
    private static let jeffyNearADollarFifty: UInt64 = 1_500_000_000_000

    /// Prices Jeffy, so a payment in it can run.
    private func priceJeffy(_ f: Fixture) async {
        await f.container.ratesController.verifiedProtoService.saveReserveStates([
            .freshReserve(mint: .jeffy, supplyFromBonding: UInt64(10_000) * 10_000_000_000)
        ])
    }

    /// Picks `mint` from the sheet's currency list.
    private func pick(_ mint: PublicKey, in f: Fixture) throws {
        let stored = try #require(f.container.session.balance(for: mint))
        f.payment.selectCurrencyAction(exchangedBalance: ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: Rate(fx: 1, currency: .usd))
        ))
    }

    @Test("Same visit: a top-up for a payment in a picked currency converts the landed Dollars into it and pays in it")
    func topUpKeepsPickInSameVisit() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 2_500_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 0, .jeffy: Self.plentyOfJeffy]
        f.topUpper.whileOrdering = { f.topUpper.delivered = f.fundingStore.pendingTopUp(for: requestID)?.amountUSD }

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.payingCurrency == PublicKey.jeffy.base58)
        try #require(plan.topUpMicros > 0)
        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .success)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.swapper.submitted.map(\.swap.source) == [.usdf])
        #expect(f.swapper.submitted.map(\.swap.destination) == [.jeffy])
        #expect(f.payer.payments.map(\.amount.mint) == [.jeffy])
        #expect(f.fundingStore.lastPaidCurrency == PublicKey.jeffy.base58)
    }

    @Test("A top-up whose conversion drains the Dollars converts once, then pays in the picked currency")
    func topUpConvertsOnceWhenItDrainsDollars() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 2_500_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 0, .jeffy: Self.plentyOfJeffy]
        f.swapper.refusesStartsAfter = 1
        f.topUpper.whileOrdering = { f.topUpper.delivered = f.fundingStore.pendingTopUp(for: requestID)?.amountUSD }

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.topUpMicros > 0)
        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .success)

        #expect(f.swapper.submitted.count == 1)
        #expect(f.swapper.refusedStarts == 0)
        #expect(f.payer.payments.map(\.amount.mint) == [.jeffy])
    }

    @Test("A conversion that leaves Dollars over converts once, then pays in the picked currency")
    func conversionWithDollarsLeftConvertsOnce() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 20_000_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 15_000_000, .jeffy: Self.plentyOfJeffy]

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.payableWithoutTopUp)
        try #require(plan.legs.contains { $0.source == PublicKey.usdf.base58 && $0.conversion })
        #expect(await f.payment.submit() == .success)

        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.map(\.amount.mint) == [.jeffy])
    }

    // MARK: - Waiting for a conversion's credit

    @Test("A top-up whose conversion credit shows a refresh late waits for it, then pays once")
    func topUpWaitsForLateConversionCredit() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 2_500_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 0, .jeffy: Self.plentyOfJeffy]
        f.swapper.balancesWhileLagging = [.usdf: 0, .jeffy: Self.jeffyNearADollarFifty]
        f.swapper.lagsRefreshes = 1
        f.topUpper.whileOrdering = { f.topUpper.delivered = f.fundingStore.pendingTopUp(for: requestID)?.amountUSD }

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.topUpMicros > 0)
        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .success)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.map(\.amount.mint) == [.jeffy])
    }

    @Test("A conversion with Dollars left over whose credit shows a refresh late converts once, then pays")
    func conversionWaitsForLateCredit() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 20_000_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 15_000_000, .jeffy: Self.plentyOfJeffy]
        f.swapper.balancesWhileLagging = [.usdf: 15_000_000, .jeffy: Self.jeffyNearADollarFifty]
        f.swapper.lagsRefreshes = 1

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        try #require(f.payment.fundingPlan?.payableWithoutTopUp == true)
        #expect(await f.payment.submit() == .success)

        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.map(\.amount.mint) == [.jeffy])
    }

    @Test("A conversion whose credit never shows stops as pending, converting once and paying nothing")
    func conversionCreditNeverShows() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 20_000_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 15_000_000, .jeffy: Self.plentyOfJeffy]
        f.swapper.balancesWhileLagging = [.usdf: 15_000_000, .jeffy: Self.jeffyNearADollarFifty]
        f.swapper.lagsRefreshes = 100

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        try #require(f.payment.fundingPlan?.payableWithoutTopUp == true)
        #expect(await f.payment.submit() == .failed)

        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem?.title == "Conversion Pending")
    }

    @Test("Relaunched between Apple Pay and the Dollars landing: the payment converts them into the picked currency and pays in it")
    func relaunchKeepsPickedCurrency() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 6, dollars: 2_500_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.swapper.balancesAfterStart = [.usdf: 0, .jeffy: Self.plentyOfJeffy]
        f.topUpper.orderResult = .mayDeliver
        var recordWhileOrdering: CollectionFundingStore.PendingTopUp?
        f.topUpper.whileOrdering = { recordWhileOrdering = f.fundingStore.pendingTopUp(for: requestID) }

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        let plan = try #require(f.payment.fundingPlan)
        try #require(plan.payingCurrency == PublicKey.jeffy.base58)
        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .failed)
        let record = try #require(recordWhileOrdering)
        #expect(record.amountUSD == 5)
        // Written before Apple Pay opened, with the currency the plan paid in.
        #expect(record.payingCurrency == PublicKey.jeffy.base58)

        // The Dollars alone would cover the payment now, so the default currency would pay without a conversion.
        let relaunched = try await relaunch(f, server)
        relaunched.topUpper.delivered = record.amountUSD
        #expect(await relaunched.payment.prepare() == .ready)
        #expect(await relaunched.payment.resumePendingTopUp() == .success)

        #expect(relaunched.topUpper.orders.isEmpty)
        #expect(f.topUpper.orders.count == 1)
        #expect(f.swapper.submitted.map(\.swap.source) == [.usdf])
        #expect(f.swapper.submitted.map(\.swap.destination) == [.jeffy])
        #expect(f.payer.payments.map(\.amount.mint) == [.jeffy])
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("A recorded currency that can't be paid in any more stops on the short state: nothing pays in another currency")
    func recordedCurrencyNoLongerPayable() async throws {
        // Jeffy is neither held nor stored, so the plan can't name it.
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 2_500_000, jeffy: nil)
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 2.5, placedAt: .now, authorized: true, payingCurrency: PublicKey.jeffy.base58),
            for: requestID
        )
        f.topUpper.delivered = 5

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.resumePendingTopUp() == .short)

        #expect(f.payer.payments.isEmpty)
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.topUpper.orders.isEmpty)
        // The Dollars landed, so the record is done; the sheet now shows the plan they give.
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.usdf.base58)
        #expect(f.fundingStore.lastPaidCurrency == nil)
    }

    @Test("A currency picked again while the top-up is pending is the one that pays")
    func repickWhilePendingWins() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 2_500_000, jeffy: Self.jeffyNearADollarFifty)
        await priceJeffy(f)
        f.topUpper.orderResult = .mayDeliver

        #expect(await f.payment.prepare() == .ready)
        try pick(.jeffy, in: f)
        let plan = try #require(f.payment.fundingPlan)
        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .failed)
        let record = try #require(f.fundingStore.pendingTopUp(for: requestID))

        try pick(.usdf, in: f)
        f.topUpper.delivered = record.amountUSD
        #expect(await f.payment.resumePendingTopUp() == .success)

        #expect(f.topUpper.orders.count == 1)
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.map(\.amount.mint) == [.usdf])
    }

    @Test("A record an earlier build wrote, with no currency, still resumes: it pays in the default currency and orders nothing")
    func olderRecordWithoutCurrencyResumes() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 6, dollars: 2_500_000, jeffy: Self.jeffyNearADollarFifty)
        let json = """
        {"orderRef":"order-1","amountUSD":5,"baselineUSD":2.5,"placedAt":\(Date.now.timeIntervalSinceReferenceDate),"authorized":true}
        """
        f.defaults.set(
            [requestID.data.hexEncodedString(): Data(json.utf8)],
            forKey: "collectionFunding.pendingTopUps.\(f.container.session.userID.uuidString)"
        )
        let record = try #require(f.fundingStore.pendingTopUp(for: requestID))
        #expect(record.payingCurrency == nil)
        #expect(record.orderID == nil)
        f.topUpper.delivered = 5

        #expect(await f.payment.prepare() == .ready)
        #expect(f.payment.hasPendingTopUp)
        #expect(await f.payment.resumePendingTopUp() == .success)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.map(\.amount.mint) == [.usdf])
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("A second tap while a top-up is pending waits on it and never orders again")
    func secondTapWaitsOnPending() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.orderResult = .mayDeliver

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)
        #expect(f.container.session.dialogItem?.title == "Money Still on Its Way")
        #expect(f.container.session.dialogItem?.subtitle == "The money you added hasn’t arrived yet. Try again shortly and you won’t be charged again.")

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

    // MARK: - Retrying with a kept swap (S5)

    /// Runs a $10 payment that converts Jeffy into Dollars and ends on Conversion Pending, then
    /// leaves the swap in flight: the server reads it as SUBMITTING and the Jeffy it sold has left
    /// the wallet, so the sheet now draws a top-up. Returns the kept swap's id.
    private func keepSwapInFlight(_ f: Fixture) async throws -> SwapId {
        f.swapper.waitResult = .submitting
        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .failed)
        #expect(f.container.session.dialogItem?.title == "Conversion Pending")
        let kept = try #require(f.swapper.submitted.first?.id)
        try Self.store([.jeffy: 0], in: f.container)
        f.swapper.states[kept] = .submitting
        f.container.session.dialogItem = nil
        return kept
    }

    private func keptSwapID(_ f: Fixture) -> SwapId? {
        f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58, destination: PublicKey.usdf.base58)
    }

    @Test("A retry whose kept swap covers the payment once it lands pays without opening Apple Pay")
    func keptSwapCoversRetry() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        _ = try await keepSwapInFlight(f)
        #expect(f.payment.fundingPlan?.topUpMicros == 6_000_000)

        // The swap lands its $6 of Dollars while the retry waits on it.
        f.swapper.waitResult = .finalized
        f.swapper.balancesAfterRefresh = [.usdf: 10_000_000]
        #expect(await f.payment.addAndPay(topUpMicros: 6_000_000) == .success)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.nativeAmount.value == 10)
        #expect(f.swapper.submitted.count == 1)
        #expect(keptSwapID(f) == nil)
    }

    @Test("A retry whose kept swap lands short of a different top-up returns the short state with the new amount and orders nothing")
    func keptSwapChangesTopUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        _ = try await keepSwapInFlight(f)
        #expect(f.payment.fundingPlan?.topUpMicros == 6_000_000)

        // The swap lands $2 of the $6 it was sized for, leaving a $4 shortfall: the $5 minimum.
        f.swapper.waitResult = .finalized
        f.swapper.balancesAfterRefresh = [.usdf: 6_000_000]
        #expect(await f.payment.addAndPay(topUpMicros: 6_000_000) == .short)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)
        #expect(f.container.session.dialogItem == nil)
    }

    @Test("A retry whose kept swap still hasn't settled stops on Conversion Pending and orders nothing")
    func keptSwapStillPending() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        let kept = try await keepSwapInFlight(f)

        #expect(await f.payment.addAndPay(topUpMicros: 6_000_000) == .failed)

        #expect(f.container.session.dialogItem?.title == "Conversion Pending")
        #expect(f.container.session.dialogItem?.subtitle == "Your conversion is still pending. Try again shortly.")
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(keptSwapID(f) == kept)
    }

    @Test("A retry sizes the top-up and reads its Dollars baseline after the kept swap lands")
    func topUpSizedAfterKeptSwapSettles() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 5_500_000, jeffy: Self.plentyOfJeffy)
        _ = try await keepSwapInFlight(f)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)

        // The swap lands $4.00 of the $4.50 it was sized for; the $0.50 left still takes the $5
        // minimum, so the amount the user saw stands.
        f.swapper.waitResult = .finalized
        f.swapper.balancesAfterRefresh = [.usdf: 9_500_000]
        f.topUpper.delivered = 5
        var recordWhileOrdering: CollectionFundingStore.PendingTopUp?
        f.topUpper.whileOrdering = { recordWhileOrdering = f.fundingStore.pendingTopUp(for: requestID) }
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .success)

        #expect(f.topUpper.orders.map(\.amountUSD) == [5])
        let record = try #require(recordWhileOrdering)
        #expect(record.baselineUSD == Decimal(string: "9.5")!)
        #expect(f.payer.payments.count == 1)
        #expect(f.swapper.submitted.count == 1)
    }

    /// 200 Jeffy: enough to convert, too little to pay $10 alongside $4 of Dollars.
    private static let someJeffy: UInt64 = 2_000_000_000_000

    /// Keeps a swap from Jeffy into Dollars that an earlier attempt started and whose funding never
    /// landed: the server holds it CREATED, its Jeffy is still in the wallet, and GetPendingSwaps
    /// lists it under the funding id it was started with. Returns its id.
    private func keepSwapUnfunded(_ f: Fixture) -> SwapId {
        let ids = CollectionFundingStore.LegIDs(swapID: .generate(), fundingIntentID: PublicKey.generate()!)
        f.fundingStore.setLegIDs(ids, for: requestID, source: PublicKey.jeffy.base58, destination: PublicKey.usdf.base58)
        f.swapper.states[ids.swapID] = .created
        f.swapper.pending = [
            PendingCollectionSwap(swapID: ids.swapID, fundingIntentID: ids.fundingIntentID, fromMint: .jeffy, toMint: .usdf, fundingQuarks: Self.someJeffy),
        ]
        return ids.swapID
    }

    @Test("A retry funds a CREATED kept swap before Apple Pay opens; once it lands, the top-up is the one the sheet showed and its baseline counts the swap's Dollars")
    func createdKeptSwapFundedBeforeTopUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.someJeffy)
        let kept = keepSwapUnfunded(f)
        #expect(await f.payment.prepare() == .ready)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)

        // Its Jeffy turns into $2 of Dollars; the $4 shortfall left still takes the $5 minimum.
        f.swapper.balancesAfterFund = [.usdf: 6_000_000, .jeffy: 0]
        f.topUpper.delivered = 5
        var fundedWhileOrdering: [SwapId]?
        var recordWhileOrdering: CollectionFundingStore.PendingTopUp?
        f.topUpper.whileOrdering = {
            fundedWhileOrdering = f.swapper.funded
            recordWhileOrdering = f.fundingStore.pendingTopUp(for: requestID)
        }
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .success)

        #expect(fundedWhileOrdering == [kept])
        #expect(f.topUpper.orders.map(\.amountUSD) == [5])
        let record = try #require(recordWhileOrdering)
        #expect(record.baselineUSD == 6)
        #expect(f.swapper.funded == [kept])
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.count == 1)
        #expect(keptSwapID(f) == nil)
    }

    @Test("A retry whose CREATED kept swap's Jeffy was spent elsewhere orders nothing while the server refuses its funding, then tops up from what's left once the server cancels it")
    func createdKeptSwapSourceSpentElsewhere() async throws {
        // The Jeffy the swap was started from is gone, so the plan reads $4 of Dollars alone.
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: nil)
        let kept = keepSwapUnfunded(f)
        #expect(await f.payment.prepare() == .ready)
        #expect(f.payment.fundingPlan?.topUpMicros == 6_000_000)

        struct Refused: Error {}
        f.swapper.fundError = Refused()
        #expect(await f.payment.addAndPay(topUpMicros: 6_000_000) == .failed)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(keptSwapID(f) == kept)
        #expect(f.container.session.dialogItem?.title == "Couldn't Send")

        // The server cancels a swap left unfunded past its funding timeout.
        f.swapper.fundError = nil
        f.swapper.states[kept] = .cancelled
        f.topUpper.delivered = 6
        #expect(await f.payment.addAndPay(topUpMicros: 6_000_000) == .success)

        #expect(f.topUpper.orders.map(\.amountUSD) == [6])
        #expect(f.swapper.funded.isEmpty)
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.count == 1)
        #expect(keptSwapID(f) == nil)
    }

    @Test("A retry sizes the top-up after its CREATED kept swap lands: one that lands short orders nothing and returns the short state with the new amount")
    func createdKeptSwapLandsShort() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.someJeffy)
        let kept = keepSwapUnfunded(f)
        #expect(await f.payment.prepare() == .ready)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)

        // The price fell before it landed: it delivers $0.50, leaving a $5.50 shortfall.
        f.swapper.balancesAfterFund = [.usdf: 4_500_000, .jeffy: 0]
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .short)

        #expect(f.swapper.funded == [kept])
        #expect(f.swapper.submitted.isEmpty)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_500_000)
        #expect(f.container.session.dialogItem == nil)
        #expect(keptSwapID(f) == nil)
    }

    @Test("A retry whose kept swap was cancelled reads the returned funds before sizing, and pays without opening Apple Pay")
    func cancelledKeptSwapReturnsFunds() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        let kept = try await keepSwapInFlight(f)
        #expect(f.payment.fundingPlan?.topUpMicros == 6_000_000)

        // Cancelled before the retry asks: the Jeffy came back, and a fresh swap converts it.
        f.swapper.states[kept] = .cancelled
        f.swapper.waitResult = .finalized
        f.swapper.balancesAfterRefresh = [.jeffy: Self.plentyOfJeffy]
        f.swapper.balancesAfterStart = [.usdf: 10_500_000]
        #expect(await f.payment.addAndPay(topUpMicros: 6_000_000) == .success)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.count == 1)
        #expect(f.swapper.submitted.count == 2)
        #expect(f.swapper.submitted.last?.id != kept)
    }

    @Test("A kept swap landing as the sheet closes pays nothing and orders nothing; the next attempt pays from its Dollars")
    func sheetClosesAsKeptSwapLands() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        _ = try await keepSwapInFlight(f)

        f.swapper.waitResult = .finalized
        f.swapper.balancesAfterRefresh = [.usdf: 10_000_000]
        f.swapper.cancelsAtRefresh = true
        #expect(await Task { await f.payment.addAndPay(topUpMicros: 6_000_000) }.value == .failed)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem == nil)
        #expect(keptSwapID(f) == nil)

        #expect(await f.payment.submit() == .success)
        #expect(f.payer.payments.count == 1)
        #expect(f.topUpper.orders.isEmpty)
    }

    @Test("A kept swap landing short as the sheet closes opens no Apple Pay and writes no top-up record")
    func sheetClosesAsKeptSwapLandsShort() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 5_500_000, jeffy: Self.plentyOfJeffy)
        _ = try await keepSwapInFlight(f)
        #expect(f.payment.fundingPlan?.topUpMicros == 5_000_000)

        // The swap leaves $0.50 short, which still takes the $5 the user saw.
        f.swapper.waitResult = .finalized
        f.swapper.balancesAfterRefresh = [.usdf: 9_500_000]
        f.swapper.cancelsAtRefresh = true
        #expect(await Task { await f.payment.addAndPay(topUpMicros: 5_000_000) }.value == .failed)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem == nil)
    }

    @Test("The sheet closing while a kept swap is waited on shows no dialog, orders nothing and keeps its ids")
    func sheetClosesWhileKeptSwapSettles() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy)
        let kept = try await keepSwapInFlight(f)

        f.swapper.waitError = CancellationError()
        let run = Task { await f.payment.addAndPay(topUpMicros: 6_000_000) }
        f.swapper.whileWaiting = { run.cancel() }
        #expect(await run.value == .failed)

        #expect(f.container.session.dialogItem == nil)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
        #expect(keptSwapID(f) == kept)
    }

    // MARK: - An authorized order Coinbase reports failed

    @Test("An authorized order Coinbase reads back as failed clears its record, says so, and the next tap orders again")
    func authorizedOrderReadBackFailed() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.orderResult = .mayDeliver
        f.topUpper.coinbaseOrderID = "cb-1"
        // Asked once, when the Dollars wait runs out.
        f.topUpper.orderFailedResults = [true]

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)

        #expect(f.topUpper.lookups == ["cb-1"])
        #expect(f.container.session.dialogItem?.title == "Something Went Wrong")
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(!f.payment.blocksDismiss)
        #expect(f.payer.payments.isEmpty)

        f.container.session.dialogItem = nil
        f.topUpper.orderResult = .charged
        f.topUpper.delivered = 5
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .success)
        #expect(f.topUpper.orders.count == 2)
        #expect(f.payer.payments.count == 1)
    }

    @Test("A kept authorized record whose order Coinbase reads back as failed clears without waiting for Dollars")
    func keptOrderReadBackFailedSkipsWait() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: .now, authorized: true, orderID: "cb-1"),
            for: requestID
        )
        f.topUpper.orderFailedResults = [true]

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.resumePendingTopUp() == .failed)

        #expect(f.topUpper.lookups == ["cb-1"])
        #expect(f.topUpper.waits == 0)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.container.session.dialogItem?.title == "Something Went Wrong")
        #expect(!f.payment.blocksDismiss)
    }

    @Test("An order Coinbase can't report failed keeps its record and its id, and shows Money Still on Its Way")
    func orderNotReadBackFailedKeepsRecord() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.orderResult = .mayDeliver
        f.topUpper.coinbaseOrderID = "cb-1"

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .failed)

        #expect(f.topUpper.lookups == ["cb-1"])
        #expect(f.container.session.dialogItem?.title == "Money Still on Its Way")
        #expect(f.fundingStore.pendingTopUp(for: requestID)?.orderID == "cb-1")
        #expect(f.fundingStore.pendingTopUp(for: requestID)?.authorized == true)
    }

    @Test("This attempt's own order waits for its Dollars and pays without asking Coinbase about it", arguments: [true, false])
    func ownOrderPaysWithoutLookup(committed: Bool) async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        f.topUpper.orderResult = committed ? .charged : .mayDeliver
        f.topUpper.coinbaseOrderID = "cb-1"
        f.topUpper.delivered = 5

        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.addAndPay(topUpMicros: 5_000_000) == .success)

        #expect(f.topUpper.lookups.isEmpty)
        #expect(f.topUpper.waits == 1)
        #expect(f.payer.payments.count == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("The sheet leaves Finishing Payment before a new Apple Pay order, when the top-up it waited on charged nothing")
    func requestScreenSheetLeavesFinishingBeforeNewOrder() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        // An earlier tap's Apple Pay never reported authorized, and its Dollars never come.
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-0", amountUSD: 10, baselineUSD: 0, placedAt: .now, authorized: false),
            for: requestID
        )
        f.topUpper.holdsWait = true
        let flow = PaymentRequestPayFlow()
        var pageWhileOrdering: CollectionPaySheetPage?
        var pageAtRefresh: CollectionPaySheetPage?
        f.topUpper.whileOrdering = {
            pageWhileOrdering = self.sheetPage(f.payment)
            f.topUpper.delivered = 10
        }

        let tap = Task { await tapTopUp(f, flow, micros: 10_000_000, refreshed: { pageAtRefresh = self.sheetPage(f.payment) }) }
        while f.topUpper.releaseWait == nil { await Task.yield() }
        try #require(f.payment.isFinishing)
        #expect(flow.isPaying)
        #expect(sheetPage(f.payment) == .finishing)
        f.topUpper.holdsWait = false
        f.topUpper.releaseWait?()

        #expect(await tap.value == .paid(.success))
        #expect(f.topUpper.orders.count == 1)
        #expect(pageWhileOrdering == .pay)
        #expect(pageAtRefresh == .paid)
    }

    // MARK: - Holding the sheet while a payment runs

    /// A record for $5 an earlier attempt ordered over $6 of Dollars, Apple Pay authorized.
    private func pendingFive(in f: Fixture) {
        f.fundingStore.setPendingTopUp(
            .init(orderRef: "order-1", amountUSD: 5, baselineUSD: 6, placedAt: .now, authorized: true),
            for: requestID
        )
    }

    @Test("A sheet opened over a top-up still to pick up shows Finishing Payment from its first frame and can't be swiped away until it pays")
    func opensOnFinishingOverPendingTopUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        pendingFive(in: f)
        f.topUpper.delivered = 5
        f.topUpper.holdsWait = true
        #expect(await f.payment.prepare() == .ready)

        f.payment.sheetWillOpen()
        // Before the sheet's task has started the pickup.
        #expect(f.payment.showsFinishing)
        #expect(f.payment.blocksDismiss)

        let pickup = Task { await f.payment.resumePendingTopUp() }
        while f.topUpper.releaseWait == nil { await Task.yield() }
        #expect(f.payment.showsFinishing)
        #expect(f.payment.blocksDismiss)
        f.topUpper.releaseWait?()

        #expect(await pickup.value == .success)
        #expect(f.payer.payments.count == 1)
        #expect(!f.payment.showsFinishing)
        #expect(!f.payment.blocksDismiss)
    }

    @Test("Finishing Payment whose submission never answers unlocks at its deadline with Payment Not Confirmed, its record gone")
    func finishingSubmissionNeverAnswers() async throws {
        let f = try await fixture(
            Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil,
            submissionTimeout: .milliseconds(200)
        )
        pendingFive(in: f)
        f.topUpper.delivered = 5
        #expect(await f.payment.prepare() == .ready)
        f.payer.holdsPayments = true
        defer { f.payer.answerHeldPayments() }
        var lockedMidPay = false
        var finishingMidPay = false
        f.payer.whilePaying = {
            lockedMidPay = f.payment.blocksDismiss
            finishingMidPay = f.payment.showsFinishing
        }

        f.payment.sheetWillOpen()
        #expect(await f.payment.resumePendingTopUp() == .failed)

        #expect(lockedMidPay)
        #expect(finishingMidPay)
        #expect(f.payer.payments.count == 1)
        #expect(!f.payment.showsFinishing)
        #expect(!f.payment.blocksDismiss)
        #expect(f.container.session.dialogItem?.title == "Payment Not Confirmed")
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("The Request screen opens the sheet over a top-up still to pick up on Finishing Payment")
    func flowOpensSheetOnFinishingOverPendingTopUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 10_000_000, jeffy: nil)
        pendingFive(in: f)
        let flow = PaymentRequestPayFlow()

        #expect(await flow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment) == .ready)

        #expect(flow.isPaying)
        #expect(f.payment.showsFinishing)
        #expect(f.payment.blocksDismiss)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("A pickup that stops on money still on its way keeps the record and lets the sheet go")
    func stoppedPickupReleasesSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        pendingFive(in: f)
        #expect(await f.payment.prepare() == .ready)

        f.payment.sheetWillOpen()
        try #require(f.payment.blocksDismiss)
        #expect(await f.payment.resumePendingTopUp() == .failed)

        #expect(f.fundingStore.pendingTopUp(for: requestID) != nil)
        #expect(!f.payment.showsFinishing)
        #expect(!f.payment.blocksDismiss)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("A record gone by the time the pickup runs leaves the sheet on the pay content, free to close")
    func recordGoneBeforePickupReleasesSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        pendingFive(in: f)
        #expect(await f.payment.prepare() == .ready)

        f.payment.sheetWillOpen()
        try #require(f.payment.showsFinishing)
        f.fundingStore.clearPendingTopUp(for: requestID)
        #expect(await f.payment.resumePendingTopUp() == nil)

        #expect(!f.payment.showsFinishing)
        #expect(!f.payment.blocksDismiss)
    }

    @Test("Add holds the sheet from Apple Pay to the payment, without showing Finishing Payment before Apple Pay ends")
    func addHoldsSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        #expect(await f.payment.prepare() == .ready)
        f.payment.sheetWillOpen()
        #expect(!f.payment.showsFinishing)
        #expect(!f.payment.blocksDismiss)
        let plan = try #require(f.payment.fundingPlan)
        f.topUpper.delivered = Decimal(plan.topUpMicros) / 1_000_000
        var heldWhileOrdering = false
        var finishingWhileOrdering = true
        f.topUpper.whileOrdering = {
            heldWhileOrdering = f.payment.blocksDismiss
            finishingWhileOrdering = f.payment.showsFinishing
        }

        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .success)

        #expect(heldWhileOrdering)
        #expect(!finishingWhileOrdering)
        #expect(!f.payment.blocksDismiss)
    }

    @Test("A swipe holds the sheet while it pays, and lets it go whether the payment lands or fails")
    func swipeHoldsSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 20_000_000, jeffy: nil)
        #expect(await f.payment.prepare() == .ready)
        var heldWhilePaying: [Bool] = []
        f.payer.whilePaying = { heldWhilePaying.append(f.payment.blocksDismiss) }

        f.payer.failure = TestPayFailure()
        #expect(await f.payment.submit() == .failed)
        #expect(!f.payment.blocksDismiss)

        f.payer.failure = nil
        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .success)
        #expect(!f.payment.blocksDismiss)
        #expect(heldWhilePaying == [true, true])
    }

    private struct TestPayFailure: Error {}

    // MARK: - Adding money from the Request screen (S6)

    /// A tap on the Request screen's top-up button for `f`, with the amount the button showed.
    private func tapTopUp(
        _ f: Fixture,
        _ flow: PaymentRequestPayFlow,
        micros: Int64,
        verified: Bool = true,
        refreshed: @escaping @MainActor () -> Void = {}
    ) async -> PaymentRequestPayFlow.TopUpInPlaceResult {
        await flow.topUpInPlace(
            requestID,
            topUpMicros: micros,
            sessionContainer: f.container,
            router: AppRouter(),
            verified: { verified },
            refreshed: { refreshed() },
            payment: f.payment
        )
    }

    @Test("1.1: with no balance the Request button reads Pay $10.00, and a tap adds $10 and pays once, ending in the sheet")
    func requestScreenTopsUpTheAmount() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 10
        let flow = PaymentRequestPayFlow()
        var refreshes = 0

        let button = try #require(f.payment.fundingSheet?.requestTopUp)
        #expect(button == .init(micros: 10_000_000, title: "Pay $10.00", footnote: nil))
        let result = await tapTopUp(f, flow, micros: button.micros, refreshed: { refreshes += 1 })

        #expect(result == .paid(.success))
        #expect(flow.isPaying)
        #expect(sheetPage(f.payment) == .paid)
        #expect(f.container.session.dialogItem == nil)
        #expect(f.topUpper.orders.map(\.amountUSD) == [10])
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.nativeAmount.value == 10)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(refreshes == 1)
        #expect(!flow.isToppingUp)
    }

    @Test("2.1: under the Apple Pay minimum the button reads Add $5.00 and Pay $2.00 over the footnote, and a tap adds $5 and pays once")
    func requestScreenTopsUpTheMinimum() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 2, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 5
        let flow = PaymentRequestPayFlow()

        let button = try #require(f.payment.fundingSheet?.requestTopUp)
        #expect(button == .init(
            micros: 5_000_000,
            title: "Add $5.00 and Pay $2.00",
            footnote: "The minimum you can add with Apple Pay is $5."
        ))
        #expect(await tapTopUp(f, flow, micros: button.micros) == .paid(.success))

        #expect(sheetPage(f.payment) == .paid)
        #expect(f.topUpper.orders.map(\.amountUSD) == [5])
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.nativeAmount.value == 2)
    }

    @Test("A dust balance counts as none, so the button still adds the whole amount")
    func dustBalanceStillTopsUp() async throws {
        // $0.004: under half a cent.
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000, jeffy: nil)

        #expect(f.payment.fundingSheet?.requestTopUp == .init(micros: 10_000_000, title: "Pay $10.00", footnote: nil))
    }

    @Test("No balance on a last paid currency other than Dollars adds the amount with no fee, so no footnote")
    func nonDollarsLastPaidTopsUpTheAmount() async throws {
        let f = try await fixture(
            Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil,
            lastPaid: .jeffy, storesJeffyMetadata: true
        )

        #expect(f.payment.fundingSheet?.payingCurrency == PublicKey.jeffy.base58)
        #expect(f.payment.fundingPlan?.legs.map(\.feeMicros) == [0])
        #expect(f.payment.fundingSheet?.requestTopUp == .init(micros: 10_000_000, title: "Pay $10.00", footnote: nil))
    }

    @Test("A balance funding any part keeps the button on Pay; a tap the plan moved under opens the sheet and orders nothing")
    func partialBalanceOpensSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        let flow = PaymentRequestPayFlow()

        #expect(f.payment.fundingSheet?.requestTopUp == nil)
        // The button drew "Pay $10.00" before $6 landed.
        #expect(await tapTopUp(f, flow, micros: 10_000_000) == .prepared(.ready))

        #expect(flow.isPaying)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("A button drawn before the top-up changed orders nothing and opens the sheet on the short state")
    func staleButtonOpensShortState() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        let flow = PaymentRequestPayFlow()

        #expect(await tapTopUp(f, flow, micros: 5_000_000) == .paid(.short))

        #expect(flow.isPaying)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("Backing out of verification opens no Apple Pay, orders nothing and pays nothing")
    func declinedVerificationOrdersNothing() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        let flow = PaymentRequestPayFlow()

        #expect(await tapTopUp(f, flow, micros: 10_000_000, verified: false) == .notVerified)

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(!flow.isToppingUp)
    }

    @Test("Over the send limit, a tap on the Request button opens no Apple Pay and orders nothing")
    func requestScreenOverSendLimit() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil, sendLimit: 8)
        let flow = PaymentRequestPayFlow()

        #expect(await tapTopUp(f, flow, micros: 10_000_000) == .paid(.failed))

        #expect(f.topUpper.orders.isEmpty)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem?.title == "Transaction Limit Reached")
    }

    @Test("The next tap waits on the top-up an earlier tap ordered and never orders again")
    func nextTapWaitsOnKeptTopUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.orderResult = .mayDeliver
        let flow = PaymentRequestPayFlow()

        #expect(await tapTopUp(f, flow, micros: 10_000_000) == .paid(.failed))
        #expect(f.container.session.dialogItem?.title == "Money Still on Its Way")
        #expect(f.container.session.dialogItem?.subtitle == "The money you added hasn’t arrived yet. Try again shortly and you won’t be charged again.")
        #expect(f.fundingStore.pendingTopUp(for: requestID)?.authorized == true)
        // The Dollars haven't landed, so the button still adds the money.
        #expect(flow.inPlaceTopUp(for: requestID)?.micros == 10_000_000)

        f.topUpper.delivered = 10
        #expect(await tapTopUp(f, flow, micros: 10_000_000) == .paid(.success))

        #expect(f.topUpper.orders.count == 1)
        #expect(f.payer.payments.count == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("Relaunched with a kept top-up, the Request button waits on it, pays once and orders nothing")
    func relaunchedRequestButtonWaitsOnKeptTopUp() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.orderResult = .mayDeliver
        #expect(await tapTopUp(f, PaymentRequestPayFlow(), micros: 10_000_000) == .paid(.failed))

        let relaunched = try await relaunch(f, server)
        relaunched.topUpper.delivered = 10
        #expect(await tapTopUp(relaunched, PaymentRequestPayFlow(), micros: 10_000_000) == .paid(.success))

        #expect(relaunched.topUpper.orders.isEmpty)
        #expect(f.topUpper.orders.count == 1)
        #expect(f.payer.payments.count == 1)
        #expect(f.fundingStore.pendingTopUp(for: requestID) == nil)
    }

    @Test("A kept top-up resumes in the collection's own currency, not the wallet's selected one")
    func keptTopUpResumesInCollectionCurrency() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: nil, jeffy: nil, storesJeffyMetadata: true)
        f.topUpper.orderResult = .mayDeliver
        #expect(await tapTopUp(f, PaymentRequestPayFlow(), micros: 10_000_000) == .paid(.failed))

        // Between attempts the wallet moved to Canadian dollars and Jeffy; the collection didn't.
        f.container.ratesController.configureTestRates(
            balanceCurrency: .cad,
            rates: [Rate(fx: 1.0, currency: .usd), Rate(fx: 1.4, currency: .cad)]
        )
        f.container.ratesController.selectToken(.jeffy, source: .user)

        let relaunched = try await relaunch(f, server)
        relaunched.topUpper.delivered = 10
        #expect(await tapTopUp(relaunched, PaymentRequestPayFlow(), micros: 10_000_000) == .paid(.success))

        #expect(relaunched.topUpper.orders.isEmpty)
        #expect(f.payer.payments.count == 1)
        #expect(f.payer.payments.first?.amount.mint == .usdf)
        #expect(f.payer.payments.first?.amount.nativeAmount == FiatAmount(value: 10, currency: .usd))
    }

    @Test("1.3: the sheet shows Finishing Payment, then reads paid through the refetch, and a second tap meanwhile does nothing")
    func secondTapDuringRunDoesNothing() async throws {
        let server = Server(intentResult: .success(intentID))
        let f = try await fixture(server, amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 10
        f.topUpper.holdsWait = true
        let flow = PaymentRequestPayFlow()
        var pageAtRefresh: CollectionPaySheetPage?

        let first = Task { await tapTopUp(f, flow, micros: 10_000_000, refreshed: { pageAtRefresh = self.sheetPage(f.payment) }) }
        while f.topUpper.releaseWait == nil { await Task.yield() }
        #expect(flow.isToppingUp)
        #expect(sheetPage(f.payment) == .finishing)

        let reads = server.intentReads
        #expect(await tapTopUp(f, flow, micros: 10_000_000) == .busy)
        #expect(await flow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment) == .failed)
        #expect(server.intentReads == reads)

        f.topUpper.releaseWait?()
        #expect(await first.value == .paid(.success))

        #expect(pageAtRefresh == .paid)
        #expect(!flow.isToppingUp)
        #expect(f.topUpper.orders.count == 1)
        #expect(f.topUpper.waits == 1)
        #expect(f.payer.payments.count == 1)
    }

    // MARK: - Finishing Payment in the sheet

    /// The page the funded-collection sheet draws for `payment`, with Payment Details closed.
    private func sheetPage(_ payment: PaymentRequestPayment) -> CollectionPaySheetPage {
        CollectionPaySheetPage(
            wantsDetails: false,
            isFinishing: payment.showsFinishing,
            isPaid: payment.hasPaidFromTopUp,
            content: payment.fundingSheet
        )
    }

    @Test("1.3: the Request button's top-up shows Finishing Payment in the swipe sheet, locked, once Apple Pay ends")
    func requestButtonFinishesInSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 10
        f.topUpper.holdsWait = true
        let flow = PaymentRequestPayFlow()
        var sheetWhileOrdering: Bool?
        f.topUpper.whileOrdering = { sheetWhileOrdering = flow.isPaying }
        var refetches = 0

        let tap = Task { await tapTopUp(f, flow, micros: 10_000_000, refreshed: { refetches += 1 }) }
        while f.topUpper.releaseWait == nil { await Task.yield() }
        try #require(f.payment.isFinishing)

        #expect(sheetWhileOrdering == false)
        #expect(flow.isPaying)
        #expect(sheetPage(f.payment) == .finishing)
        #expect(f.payment.blocksDismiss)

        // The sheet's open task joins the run rather than ordering again.
        let sheetOpen = Task { await f.payment.resumePendingTopUp() }
        f.topUpper.releaseWait?()
        #expect(await tap.value == .paid(.success))
        _ = await sheetOpen.value
        #expect(f.topUpper.orders.count == 1)
        #expect(f.payer.payments.count == 1)
        #expect(refetches == 1)
        #expect(flow.isPaying)
        #expect(sheetPage(f.payment) == .paid)
    }

    @Test("1.1: a chat Pay with no balance shows Finishing Payment in the swipe sheet over the Request screen")
    func chatPayFinishesInSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 10
        f.topUpper.holdsWait = true
        let chatFlow = PaymentRequestPayFlow()
        let screenFlow = PaymentRequestPayFlow()
        #expect(await chatFlow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment) == .fundedByTopUp)

        // The Request screen opens on paysOnOpen and runs its button with its own flow.
        let tap = Task { await tapRequestButton(f, screenFlow, topUp: screenFlow.inPlaceTopUp(for: requestID)) }
        while f.topUpper.releaseWait == nil { await Task.yield() }

        #expect(!chatFlow.isPaying)
        #expect(screenFlow.isPaying)
        #expect(sheetPage(f.payment) == .finishing)

        f.topUpper.releaseWait?()
        #expect(await tap.value == .paid(.success))
    }

    @Test("Once the money the sheet's Add button added pays, the sheet stops drawing the swipe")
    func sheetAddEndsOffTheSwipe() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        #expect(await f.payment.prepare() == .ready)
        f.payment.sheetWillOpen()
        let plan = try #require(f.payment.fundingPlan)
        f.topUpper.delivered = Decimal(plan.topUpMicros) / 1_000_000

        #expect(await f.payment.addAndPay(topUpMicros: plan.topUpMicros) == .success)

        #expect(sheetPage(f.payment) == .paid)
    }

    @Test("A top-up picked up as the sheet opens stops drawing the swipe once it pays")
    func resumedTopUpEndsOffTheSwipe() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        pendingFive(in: f)
        f.topUpper.delivered = 5
        #expect(await f.payment.prepare() == .ready)
        f.payment.sheetWillOpen()

        #expect(await f.payment.resumePendingTopUp() == .success)

        #expect(f.payer.payments.count == 1)
        #expect(sheetPage(f.payment) == .paid)
    }

    @Test("A swiped payment keeps the swipe page, whose own checkmark shows until the sheet closes")
    func swipeKeepsThePayPage() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 10_000_000, jeffy: nil)
        #expect(await f.payment.prepare() == .ready)
        f.payment.sheetWillOpen()

        #expect(await f.payment.submit() == .success)

        #expect(!f.payment.hasPaidFromTopUp)
        #expect(sheetPage(f.payment) == .pay)
    }

    @Test("Reopening the sheet after a top-up paid draws it fresh")
    func reopenClearsPaid() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        pendingFive(in: f)
        f.topUpper.delivered = 5
        #expect(await f.payment.prepare() == .ready)
        f.payment.sheetWillOpen()
        #expect(await f.payment.resumePendingTopUp() == .success)

        f.payment.sheetWillOpen()

        #expect(!f.payment.hasPaidFromTopUp)
    }

    @Test("With Group Money off the Request button stays Pay and a tap orders nothing")
    func requestScreenFlagOff() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil, fundsCollections: false)
        let flow = PaymentRequestPayFlow()

        let result = await tapTopUp(f, flow, micros: 10_000_000)

        guard case .prepared = result else {
            Issue.record("Expected the shipped Pay path, got \(result)")
            return
        }
        #expect(flow.inPlaceTopUp(for: requestID) == nil)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
    }

    // MARK: - Pay from the chat

    /// The Request screen's button as `flow` runs it, showing `topUp`, or Pay when nil.
    private func tapRequestButton(
        _ f: Fixture,
        _ flow: PaymentRequestPayFlow,
        topUp: CollectionPaymentSheetContent.RequestTopUp?
    ) async -> PaymentRequestPayFlow.TopUpInPlaceResult {
        await flow.payFromRequestScreen(
            requestID,
            topUp: topUp,
            sessionContainer: f.container,
            router: AppRouter(),
            verified: { true },
            refreshed: {},
            payment: f.payment
        )
    }

    @Test("1.1: a chat Pay with no balance hands off to the Request screen, which orders once and pays")
    func chatPayTopsUpOnRequestScreen() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 10
        let chatFlow = PaymentRequestPayFlow()
        let screenFlow = PaymentRequestPayFlow()

        #expect(await chatFlow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment) == .fundedByTopUp)
        #expect(f.topUpper.orders.isEmpty)
        // The screen opens with its own flow and runs its button, which reads its own plan.
        let result = await tapRequestButton(f, screenFlow, topUp: screenFlow.inPlaceTopUp(for: requestID))

        #expect(result == .paid(.success))
        #expect(!chatFlow.isPaying)
        #expect(sheetPage(f.payment) == .paid)
        #expect(f.container.session.dialogItem == nil)
        #expect(f.topUpper.orders.map(\.amountUSD) == [10])
        #expect(f.payer.payments.count == 1)
    }

    @Test("A chat Pay with a balance funding part of the collection opens the sheet and orders nothing")
    func chatPayPartialBalanceOpensSheet() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 6_000_000, jeffy: nil)
        let flow = PaymentRequestPayFlow()

        #expect(await flow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment) == .ready)

        #expect(flow.isPaying)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("A Request button drawn as Pay before the balance went adds the money and pays once")
    func requestPayButtonOverNoBalanceTopsUp() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil)
        f.topUpper.delivered = 10
        let flow = PaymentRequestPayFlow()

        #expect(await tapRequestButton(f, flow, topUp: nil) == .paid(.success))

        #expect(sheetPage(f.payment) == .paid)
        #expect(f.topUpper.orders.map(\.amountUSD) == [10])
        #expect(f.payer.payments.count == 1)
    }

    @Test("With Group Money off a chat Pay at a zero balance keeps the shipped No Balance Yet and orders nothing")
    func chatPayFlagOff() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: nil, jeffy: nil, fundsCollections: false)
        let flow = PaymentRequestPayFlow()

        #expect(await flow.start(requestID, sessionContainer: f.container, router: AppRouter(), payment: f.payment) == .noBalance)

        #expect(!flow.isPaying)
        #expect(f.container.session.dialogItem != nil)
        #expect(f.topUpper.orders.isEmpty)
        #expect(f.payer.payments.isEmpty)
    }

    @Test("With Group Money off a collection neither plans nor converts, and the sheet stays the shipped one")
    func flagOff() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 4_000_000, jeffy: Self.plentyOfJeffy, fundsCollections: false)

        // The sheet's handle, pill chevron, picker and Payment Details page each switch on this.
        #expect(!f.payment.fundsCollection)
        #expect(f.payment.fundingPlan == nil)
        #expect(f.payment.fundingSheet == nil)
        #expect(CollectionPaySheetPage(wantsDetails: true, isFinishing: false, content: f.payment.fundingSheet) == .pay)
        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .failed)
        #expect(f.swapper.submitted.isEmpty)
    }
}
