//
//  PaymentRequestPayment.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Pays the viewer's part of one payment request to its creator: their share of a split, or a
/// collection's fixed amount.
///
/// The part is paid under the intent ID the server issued for it, so a retry, a second tap or a
/// second device can land only once. That ID is held in memory for this payment only and never
/// logged: anyone holding it before the part is paid can use it up.
@MainActor
@Observable
final class PaymentRequestPayment {

    enum Outcome: Equatable {
        case success
        case failed
    }

    /// What ``prepare()`` found.
    enum Preparation: Equatable {
        /// The share is payable; show the swipe sheet.
        case ready
        /// The viewer has no unpaid share any more; the screen already shows the fetched request.
        case nothingToPay
        /// The request stopped accepting payments; "Request Closed" was shown.
        case closed
        case failed
        /// The viewer holds nothing to pay with; the "No Balance Yet" dialog was shown.
        case noBalance
    }

    /// What the viewer pays: an unpaid share of a split, or a collection's fixed amount in the
    /// request's currency.
    enum Payable: Equatable {
        case share(GroupPaymentRequest.Share)
        case fixed(nativeAmount: Double)
    }

    /// The request and what the viewer pays as they read when the swipe sheet opened.
    struct SheetSnapshot: Equatable {
        let request: GroupPaymentRequest
        let payable: Payable
    }

    let requestID: PaymentRequestID

    /// What the swipe sheet shows, taken when ``prepare()`` finds the share payable; it outlives
    /// the share reading paid, so the sheet keeps its amount through success and dismiss.
    private(set) var sheetSnapshot: SheetSnapshot?

    private(set) var selectedBalance: ExchangedBalance?
    /// The currency picked in this sheet for a funded collection; nil until a pick, so the plan
    /// opens on the last paid currency, or Dollars before any.
    private(set) var pickedCurrency: PublicKey?
    /// Set when the insufficient-funds dialog's Add Money is tapped; the presenter routes to the deposit and clears it.
    var depositMint: PublicKey?

    @ObservationIgnored private let requests: PaymentRequests
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let payer: any RequestedPaying
    @ObservationIgnored private let resolver: any RecipientResolving
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let fundingStore: CollectionFundingStore
    @ObservationIgnored private let fundingExecutor: CollectionFundingExecutor
    @ObservationIgnored private let fundsCollections: () -> Bool
    @ObservationIgnored private var intentID: Data?
    /// Set after a payment whose outcome isn't known, so the next try refetches first.
    @ObservationIgnored private var needsRefetch = false

    init(
        requestID: PaymentRequestID,
        sessionContainer: SessionContainer,
        requests: PaymentRequests? = nil,
        payer: (any RequestedPaying)? = nil,
        resolver: (any RecipientResolving)? = nil,
        swapper: (any CollectionSwapping)? = nil,
        fundingStore: CollectionFundingStore? = nil,
        fundsCollections: (() -> Bool)? = nil,
        clock: @escaping () -> Date = Date.init
    ) {
        let session = sessionContainer.session
        let fundingStore = fundingStore ?? CollectionFundingStore(userID: session.userID)
        self.requestID = requestID
        self.requests = requests ?? sessionContainer.paymentRequests
        self.session = session
        self.ratesController = sessionContainer.ratesController
        self.payer = payer ?? session
        self.resolver = resolver ?? session
        self.clock = clock
        self.fundingStore = fundingStore
        self.fundingExecutor = CollectionFundingExecutor(
            swapper: swapper ?? SessionCollectionSwapper(session: session, ratesController: sessionContainer.ratesController),
            store: fundingStore
        )
        self.fundsCollections = fundsCollections ?? {
            BetaFlags.shared.showsGroupMoneyUI(isStaff: BetaFlags.shared.staffStanding(of: session))
        }
        self.selectedBalance = sessionContainer.ratesController.resolveInitialBalance(mint: nil, session: session)
    }

    var request: GroupPaymentRequest? {
        requests.request(requestID)
    }

    /// The viewer's unpaid share, nil once paid.
    var share: GroupPaymentRequest.Share? {
        guard let own = request?.share(for: session.userID), !own.isPaid else { return nil }
        return own
    }

    /// What the viewer still pays: their unpaid share of a split, or a collection's fixed amount
    /// until a read says they've paid it. `nil` when there is nothing to pay.
    var payable: Payable? {
        guard let request else { return nil }
        guard let collection = request.collection else { return share.map(Payable.share) }
        guard requests.payers.hasPaid(requestID, viewer: session.userID) != true else { return nil }
        switch collection.paymentAmount {
        case .fixed(let fixed):
            return .fixed(nativeAmount: fixed.nativeAmount)
        case nil:
            return nil
        }
    }

    /// The balances the currency picker offers. A funded collection also offers the paying
    /// currency at zero, since conversions can fund it.
    var paymentOptions: [ExchangedBalance] {
        let options = ratesController.paymentOptions(session: session)
        guard fundsCollection, let paying = payingBalance,
              !options.contains(where: { $0.stored.mint == paying.stored.mint }) else { return options }
        return [paying] + options
    }

    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        if fundsCollection {
            // Picking reruns the plan; it starts no swap and leaves the app-wide selection alone.
            pickedCurrency = exchangedBalance.stored.mint
        } else {
            ratesController.selectToken(exchangedBalance.stored.mint, source: .user)
        }
    }

    // MARK: - Collection funding -

    /// Whether this payment converts other balances to cover a collection: Group Money only.
    var fundsCollection: Bool {
        request?.collection != nil && fundsCollections()
    }

    /// How the payment would be funded from the balances held now, or nil when it can't be planned.
    var fundingPlan: CollectionFundingPlan? {
        guard fundsCollection, let request, let payable,
              let fiat = payableFiat(payable, of: request),
              let rate = ratesController.rate(for: fiat.currency) else { return nil }
        let dollars = PublicKey.usdf.base58
        var inputs = session.balances.map { stored in
            CollectionFundingBalance(
                id: stored.mint.base58,
                fiatMicros: Self.micros(stored.computeExchangedValue(with: rate).nativeAmount.value),
                sellFeeBps: Int64(stored.mint == .usdf ? LaunchpadFee.dollarsFeeBps : LaunchpadFee.poolSellFeeBps(stored.sellFeeBps))
            )
        }
        if !inputs.contains(where: { $0.id == dollars }) {
            inputs.append(CollectionFundingBalance(id: dollars, fiatMicros: 0, sellFeeBps: 0))
        }
        let held = Set(inputs.map(\.id))
        let selected = pickedCurrency.map(\.base58).flatMap { held.contains($0) ? $0 : nil }
        // A last-paid currency the wallet no longer holds can't be named or funded; open on Dollars.
        let lastPaid = fundingStore.lastPaidCurrency.flatMap { held.contains($0) ? $0 : nil }
        return try? planCollectionFunding(
            amountMicros: Self.micros(fiat.value),
            minorDigits: fiat.currency.maximumFractionDigits,
            minimumTopUpMicros: 0,
            selected: selected,
            lastPaid: lastPaid,
            dollars: dollars,
            balances: inputs
        )
    }

    /// The plan as the sheet and Payment Details draw it.
    var fundingDisplay: CollectionFundingDisplay? {
        guard let plan = fundingPlan, let request, let payable,
              let currency = payableFiat(payable, of: request)?.currency else { return nil }
        let names = Dictionary(session.balances.map { ($0.mint.base58, $0.name) }, uniquingKeysWith: { first, _ in first })
        return CollectionFundingDisplay(plan: plan, currency: currency, dollars: PublicKey.usdf.base58, names: names)
    }

    /// The paying currency's balance, for the sheet's pill; held at zero when conversions fund it.
    var payingBalance: ExchangedBalance? {
        guard let mint = fundingPlan.flatMap({ try? PublicKey(base58: $0.payingCurrency) }),
              let stored = session.balance(for: mint) else { return nil }
        return ExchangedBalance(stored: stored, exchangedFiat: stored.computeExchangedValue(with: ratesController.rateForBalanceCurrency()))
    }

    private static func micros(_ value: Decimal) -> Int64 {
        var scaled = value * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Refetches the request right before the swipe sheet shows, taking the intent ID from it. A
    /// collection's intent ID comes from its own read, which also says when there is nothing to pay.
    func prepare() async -> Preparation {
        if request?.collection != nil { return await prepareCollection() }
        do {
            intentID = try await requests.refresh(requestID)
        } catch {
            showSendError()
            return .failed
        }
        needsRefetch = false
        if !isOpen {
            intentID = nil
            showRequestClosed()
            return .closed
        }
        guard intentID != nil, let request, let share else { return .nothingToPay }
        sheetSnapshot = SheetSnapshot(request: request, payable: .share(share))
        return .ready
    }

    private func prepareCollection() async -> Preparation {
        do {
            intentID = try await requests.paymentIntentID(for: requestID)
        } catch let error as ErrorGetPaymentIntentID {
            intentID = nil
            switch error {
            case .notOpen:
                _ = try? await requests.refreshDetails(requestID)
                showRequestClosed()
                return .closed
            case .alreadyPaid, .notAPayer:
                fundingStore.clearSwapIDs(for: requestID)
                _ = try? await requests.refreshDetails(requestID)
                return .nothingToPay
            case .denied, .notFound:
                // The store marked the request unavailable; the screen says so in place of its body.
                return .nothingToPay
            case .ok, .unknown, .transportFailure, .cancelled, .rejected:
                showSendError()
                return .failed
            }
        } catch {
            intentID = nil
            showSendError()
            return .failed
        }
        needsRefetch = false
        guard let request, let payable else {
            intentID = nil
            return .nothingToPay
        }
        sheetSnapshot = SheetSnapshot(request: request, payable: payable)
        return .ready
    }

    /// `payable` in the request's currency, nil when the request's currency or amount can't be read.
    private func payableFiat(_ payable: Payable, of request: GroupPaymentRequest) -> FiatAmount? {
        let currencyCode: String?
        let nativeAmount: Double
        switch payable {
        case .share(let share):
            currencyCode = request.split?.currency
            nativeAmount = share.nativeAmount
        case .fixed(let fixed):
            currencyCode = request.collection?.currency
            nativeAmount = fixed
        }
        guard let currency = currencyCode.flatMap({ try? CurrencyCode(currencyCode: $0) }),
              let value = Decimal(string: "\(nativeAmount)") else { return nil }
        return FiatAmount(value: value, currency: currency)
    }

    /// The funding step a payment takes when the picked balance falls short: add or convert money,
    /// then return whether the balance may now cover the payment, which is then priced again at a
    /// fresh rate. Nothing funds yet, so it returns false and the insufficient-funds dialog shows.
    private func coverShortfall(_ shortfall: ExchangedFiat?, in balance: ExchangedBalance) async -> Bool {
        false
    }

    /// `fiat` priced into `mint` at a fresh rate.
    private func price(_ fiat: FiatAmount, mint: PublicKey) async -> (amount: ExchangedFiat, pin: VerifiedState)? {
        guard let pin = await ratesController.currentPinnedState(for: fiat.currency, mint: mint),
              let amount = session.price(fiat, mint: mint, at: pin) else { return nil }
        return (amount, pin)
    }

    /// Pays exactly what the viewer owes: its amount in the request's currency, priced into the
    /// picked token.
    func submit() async -> Outcome {
        if needsRefetch {
            switch await prepare() {
            case .ready: break
            case .nothingToPay where hasPaidCollection:
                // ALREADY_PAID: the attempt whose outcome was unknown landed, so don't pay again.
                return .success
            case .nothingToPay, .closed, .failed, .noBalance: return .failed
            }
        }
        if fundsCollection {
            return await submitFundedCollection()
        }
        guard let selectedBalance else {
            ErrorReporting.captureError(
                GroupSendViewModel.Error.noSpendableBalance,
                reason: "No spendable balance at request payment",
                metadata: ["requestID": "\(requestID)"]
            )
            showInsufficientFunds(shortfall: nil)
            return .failed
        }

        guard let request, let payable, let creator = request.creator,
              let intentID, let intentKey = try? PublicKey(intentID),
              let chatID = request.chatID,
              let fiat = payableFiat(payable, of: request) else {
            showSendError()
            return .failed
        }

        return await pay(fiat, as: payable, to: creator, in: chatID, intentKey: intentKey, from: selectedBalance, mayFund: true)
    }

    /// Converts what the plan needs into the paying currency, each swap settled before the next,
    /// then pays once from it. Funding runs before the funds gate because a paying currency held
    /// at zero can't be priced there.
    private func submitFundedCollection() async -> Outcome {
        guard let request, let payable, let creator = request.creator,
              let intentID, let intentKey = try? PublicKey(intentID),
              let chatID = request.chatID,
              let fiat = payableFiat(payable, of: request) else {
            showSendError()
            return .failed
        }

        switch await fundingExecutor.fund(requestID, currency: fiat.currency, plan: { self.fundingPlan }) {
        case .funded:
            break
        case .short:
            showInsufficientFunds(shortfall: fundingShortfall(in: fiat.currency))
            return .failed
        case .failed:
            // Swaps that landed stay converted; the retry reads the intent ID again before funding.
            needsRefetch = true
            showSendError()
            return .failed
        }

        guard let paying = payingBalance else {
            showInsufficientFunds(shortfall: nil)
            return .failed
        }
        selectedBalance = paying
        let outcome = await pay(fiat, as: payable, to: creator, in: chatID, intentKey: intentKey, from: paying, mayFund: false)
        if outcome == .success {
            fundingStore.recordPaid(currency: paying.stored.mint.base58)
            fundingStore.clearSwapIDs(for: requestID)
        }
        return outcome
    }

    /// What the balances fall short by, for today's short state.
    private func fundingShortfall(in currency: CurrencyCode) -> ExchangedFiat? {
        guard let plan = fundingPlan, plan.shortfallMicros > 0,
              let rate = ratesController.rate(for: currency) else { return nil }
        return ExchangedFiat(
            nativeAmount: FiatAmount(value: Decimal(plan.shortfallMicros) / 1_000_000, currency: currency),
            rate: rate
        )
    }

    private func pay(
        _ fiat: FiatAmount,
        as payable: Payable,
        to creator: UserID,
        in chatID: ConversationID,
        intentKey: PublicKey,
        from selectedBalance: ExchangedBalance,
        mayFund: Bool
    ) async -> Outcome {
        let mint = selectedBalance.stored.mint
        guard let (amount, pin) = await price(fiat, mint: mint) else {
            ErrorReporting.captureError(
                RatesController.Error.exchangeRateUnavailable,
                reason: "No fresh rate at request payment",
                metadata: ["mint": mint.base58]
            )
            session.dialogItem = .error(
                title: "Rate Unavailable",
                subtitle: "Couldn't get a fresh rate. Please try again."
            )
            return .failed
        }

        // Gate on the uncapped amount: `amount` is capped at the balance, so it always passes.
        let entered = selectedBalance.enteredFiat(for: fiat.value, rate: pin.rate)
        let uncapped: ExchangedFiat
        switch payable {
        case .share:
            uncapped = entered ?? amount
        case .fixed:
            // A collection takes only its fixed amount, so never gate on a capped one.
            guard let entered else {
                showInsufficientFunds(shortfall: nil)
                return .failed
            }
            uncapped = entered
        }
        switch session.hasSufficientFunds(for: uncapped) {
        case .insufficient(let shortfall):
            guard mayFund, await coverShortfall(shortfall, in: selectedBalance) else {
                showInsufficientFunds(shortfall: shortfall)
                return .failed
            }
            return await pay(fiat, as: payable, to: creator, in: chatID, intentKey: intentKey, from: selectedBalance, mayFund: false)
        case .sufficient:
            break
        }
        // `amount` is capped at the balance; a collection never sends less than its fixed amount.
        switch payable {
        case .fixed where !covers(amount.nativeAmount, fiat):
            showInsufficientFunds(shortfall: nil)
            return .failed
        case .fixed, .share:
            break
        }

        let sendLimit = session.sendLimitFor(currency: amount.nativeAmount.currency) ?? .zero
        guard amount.nativeAmount.value <= sendLimit.nextTransaction.value else {
            session.dialogItem = .error(
                title: "Transaction Limit Reached",
                subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily"
            )
            return .failed
        }

        let creatorOwner: PublicKey
        do {
            creatorOwner = try await resolver.resolveUserID(creator)
        } catch {
            showSendError()
            return .failed
        }

        do {
            try await payer.payRequestShare(
                amount: amount,
                verifiedState: pin,
                to: creatorOwner,
                chatID: chatID,
                paymentRequestID: requestID,
                intentID: intentKey
            )
            self.intentID = nil
            Analytics.sentCash(exchangedFiat: amount, context: .paymentRequest, error: nil)
            _ = try? await requests.refreshDetails(requestID)
            return .success
        } catch {
            Analytics.sentCash(exchangedFiat: amount, context: .paymentRequest, error: error)
            needsRefetch = true
            guard !(error is CancellationError) else { return .failed }
            // A refusal because the request ended reads as "Request Closed", not a send failure.
            _ = try? await requests.refreshDetails(requestID)
            if isOpen {
                showSendError()
            } else {
                self.intentID = nil
                showRequestClosed()
            }
            return .failed
        }
    }

    /// Whether `priced` pays `fiat` to within half its currency's smallest unit.
    private func covers(_ priced: FiatAmount, _ fiat: FiatAmount) -> Bool {
        guard priced.currency == fiat.currency else { return false }
        let halfUnit = Decimal(sign: .plus, exponent: -fiat.currency.maximumFractionDigits, significand: 5) / 10
        return priced.value >= fiat.value - halfUnit
    }

    private var hasPaidCollection: Bool {
        request?.collection != nil && requests.payers.hasPaid(requestID, viewer: session.userID) == true
    }

    private var isOpen: Bool {
        guard let request else { return false }
        switch request.effectiveStatus(at: clock()) {
        case .open:                                    return true
        case .completed, .closed, .expired, .unknown:  return false
        }
    }

    private func showInsufficientFunds(shortfall: ExchangedFiat?) {
        let title = shortfall.map { "You're \($0.nativeAmount.formatted()) Short" } ?? "You Need More Cash"
        let subtitle = shortfall == nil
            ? "Please add more cash, or select a different Community Currency"
            : "Add more cash, or select a different Community Currency"
        session.dialogItem = .error(title: title, subtitle: subtitle) {
            .destructive("Add More Cash") { [weak self] in
                self?.depositMint = self?.selectedBalance?.stored.mint ?? .usdf
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showRequestClosed() {
        session.dialogItem = .error(
            title: "Request Closed",
            subtitle: "This request is no longer accepting payments."
        )
    }

    private func showSendError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't complete the transfer. Please try again."
        )
    }
}
