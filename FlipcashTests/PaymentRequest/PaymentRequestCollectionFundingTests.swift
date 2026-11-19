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
            let balances = balancesAfterRefresh
            try container.database.transaction { db in
                for (mint, quarks) in balances {
                    try db.insertBalance(quarks: quarks, mint: mint, costBasis: 0, date: .now)
                }
            }
            for _ in 0..<500 where !balances.allSatisfy({ container.session.balance(for: $0.key)?.quarks == $0.value }) {
                await Task.yield()
            }
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
        let fundingStore: CollectionFundingStore
        let container: SessionContainer
    }

    /// A $`amount` collection payment over a wallet holding `dollars` USDF quarks and `jeffy`
    /// Jeffy quarks.
    private func fixture(
        _ server: Server,
        amount: Double,
        dollars: UInt64,
        jeffy: UInt64?,
        lastPaid: PublicKey? = nil,
        fundsCollections: Bool = true
    ) async throws -> Fixture {
        var holdings = [SessionContainer.Holding(mint: .usdf, quarks: dollars)]
        if let jeffy {
            holdings.append(SessionContainer.Holding(mint: Self.jeffyMint, quarks: jeffy))
        }
        let limit = FiatAmount(value: 1000, currency: .usd)
        let container = try SessionContainer.makeTest(
            holdings: holdings,
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
        let payment = PaymentRequestPayment(
            requestID: requestID,
            sessionContainer: container,
            requests: requests,
            payer: payer,
            resolver: payer,
            swapper: swapper,
            fundingStore: fundingStore,
            fundsCollections: { fundsCollections }
        )
        return Fixture(payment: payment, payer: payer, swapper: swapper, fundingStore: fundingStore, container: container)
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

    @Test("A last paid currency the wallet no longer holds falls back to Dollars")
    func lastPaidNotHeld() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 100_000_000, jeffy: nil, lastPaid: .jeffy)

        #expect(f.payment.fundingPlan?.payingCurrency == PublicKey.usdf.base58)
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
        #expect(f.container.session.dialogItem?.title == "Couldn't Send")

        // The swap and the payment landed after all.
        server.intentResult = .failure(.alreadyPaid)
        server.isPaid = true

        #expect(await f.payment.submit() == .success)
        #expect(server.intentReads == 2)
        #expect(f.swapper.submitted.count == 1)
        #expect(f.payer.payments.isEmpty)
        #expect(f.fundingStore.swapID(for: requestID, source: PublicKey.jeffy.base58) == nil)
    }

    @Test("A shortfall conversions can't cover shows today's short state and converts nothing")
    func uncoverableShowsShort() async throws {
        let f = try await fixture(Server(intentResult: .success(intentID)), amount: 10, dollars: 3_000_000, jeffy: nil)

        #expect(f.payment.fundingPlan?.payableWithoutTopUp == false)
        #expect(await f.payment.prepare() == .ready)
        #expect(await f.payment.submit() == .failed)

        #expect(f.swapper.submitted.isEmpty)
        #expect(f.payer.payments.isEmpty)
        #expect(f.container.session.dialogItem?.title == "You're $7.00 Short")
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
