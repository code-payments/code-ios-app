//
//  PaymentRequestPayment.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashStore

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
        /// The balances fall short, so the sheet shows the short state again and waits for the
        /// user to confirm a top-up. Nothing more was ordered.
        case short
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
        /// No balance funds the collection, so no sheet opened: the Request screen's button adds
        /// the money with Apple Pay and pays instead (1.1, 2.1).
        case fundedByTopUp
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
    /// True from Apple Pay finishing until the payment ends, while the sheet shows "Finishing Payment".
    private(set) var isFinishing = false
    /// True from the sheet opening over a top-up an earlier attempt ordered until its pickup
    /// returns, so the sheet opens on "Finishing Payment" rather than drawing the pay content first.
    private var isPickingUp = false
    /// True while a swipe's payment runs.
    private var isSubmitting = false

    /// Whether the sheet shows "Finishing Payment": added Dollars landing and paying, or a pickup due as it opens.
    var showsFinishing: Bool { isFinishing || isPickingUp }

    /// Whether a payment from the sheet is running or due to be picked up; the sheet can't be swiped away then.
    var blocksDismiss: Bool { isSubmitting || topUpRun != nil || isPickingUp }

    @ObservationIgnored private let requests: PaymentRequests
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let payer: any RequestedPaying
    @ObservationIgnored private let resolver: any RecipientResolving
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let fundingStore: CollectionFundingStore
    @ObservationIgnored private let fundingExecutor: CollectionFundingExecutor
    @ObservationIgnored private let fundsCollections: () -> Bool
    @ObservationIgnored private let topUpper: any CollectionTopUpping
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
        topUpper: (any CollectionTopUpping)? = nil,
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
        self.topUpper = topUpper ?? SessionCollectionTopUpper(
            session: session,
            coinbaseService: sessionContainer.coinbaseService,
            sweeper: sessionContainer.usdcSweepOperation
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
    /// currency and Dollars at zero, since conversions can fund either.
    var paymentOptions: [ExchangedBalance] {
        let options = ratesController.paymentOptions(session: session)
        guard fundsCollection else { return options }
        let missing = [payingBalance, balanceOrZero(for: .usdf)]
            .compactMap { $0 }
            .filter { balance in !options.contains { $0.stored.mint == balance.stored.mint } }
        var seen = Set<PublicKey>()
        return missing.filter { seen.insert($0.stored.mint).inserted } + options
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
        // A picked or last-paid currency with no balance row is still payable at zero while its
        // metadata is stored; one the app knows nothing about can't be named, so it opens on Dollars.
        let named = { (id: String) -> String? in
            if inputs.contains(where: { $0.id == id }) { return id }
            guard let mint = try? PublicKey(base58: id),
                  let metadata = self.session.storedMintMetadata(for: mint) else { return nil }
            inputs.append(CollectionFundingBalance(
                id: id,
                fiatMicros: 0,
                sellFeeBps: Int64(LaunchpadFee.poolSellFeeBps(metadata.sellFeeBps))
            ))
            return id
        }
        let selected = pickedCurrency.map(\.base58).flatMap(named)
        let lastPaid = fundingStore.lastPaidCurrency.flatMap(named)
        return try? planCollectionFunding(
            amountMicros: Self.micros(fiat.value),
            minorDigits: fiat.currency.maximumFractionDigits,
            minimumTopUpMicros: Self.minimumTopUpMicros(rate: rate, minorDigits: fiat.currency.maximumFractionDigits),
            selected: selected,
            lastPaid: lastPaid,
            dollars: dollars,
            balances: inputs
        )
    }

    /// The plan as the sheet's fee line and Payment Details draw it.
    var fundingSheet: CollectionPaymentSheetContent? {
        guard let plan = fundingPlan, let request, let payable,
              let currency = payableFiat(payable, of: request)?.currency else { return nil }
        var names = Dictionary(session.balances.map { ($0.mint.base58, $0.name) }, uniquingKeysWith: { first, _ in first })
        if names[plan.payingCurrency] == nil,
           let mint = try? PublicKey(base58: plan.payingCurrency),
           let metadata = session.storedMintMetadata(for: mint) {
            names[plan.payingCurrency] = metadata.name
        }
        let display = CollectionFundingDisplay(plan: plan, currency: currency, dollars: PublicKey.usdf.base58, names: names)
        return CollectionPaymentSheetContent(plan: plan, display: display, currency: currency)
    }

    /// The icon of the currency with this id, when the app has its metadata.
    func currencyImageURL(_ id: String) -> URL? {
        guard let mint = try? PublicKey(base58: id) else { return nil }
        return session.balance(for: mint)?.imageURL ?? session.storedMintMetadata(for: mint)?.imageURL
    }

    /// The paying currency's balance, for the sheet's pill; held at zero when conversions fund it.
    var payingBalance: ExchangedBalance? {
        fundingPlan
            .flatMap { try? PublicKey(base58: $0.payingCurrency) }
            .flatMap(balanceOrZero(for:))
    }

    /// The wallet's balance of `mint`, or a zero one while its metadata is stored.
    private func balanceOrZero(for mint: PublicKey) -> ExchangedBalance? {
        guard let stored = session.balance(for: mint) ?? Self.emptyBalance(session.storedMintMetadata(for: mint)) else { return nil }
        return ExchangedBalance(stored: stored, exchangedFiat: stored.computeExchangedValue(with: ratesController.rateForBalanceCurrency()))
    }

    /// A zero balance for a currency with no balance row yet, so the pill can name it. The planner
    /// pays in Dollars before the server has listed a Dollars account; the first leg creates it.
    private static func emptyBalance(_ metadata: StoredMintMetadata?) -> StoredBalance? {
        guard let metadata else { return nil }
        return try? StoredBalance(
            quarks: 0,
            symbol: metadata.symbol,
            name: metadata.name,
            supplyFromBonding: metadata.supplyFromBonding,
            sellFeeBps: metadata.sellFeeBps,
            mint: metadata.mint,
            vmAuthority: metadata.vmAuthority,
            updatedAt: .now,
            imageURL: metadata.imageURL,
            costBasis: 0
        )
    }

    private static func micros(_ value: Decimal) -> Int64 {
        var scaled = value * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Apple Pay's minimum purchase in `rate`'s currency, rounded up to its smallest unit, so a
    /// top-up at the minimum converts back to an order the deposit's own check accepts.
    static func minimumTopUpMicros(rate: Rate, minorDigits: Int) -> Int64 {
        let minimum = FiatAmount.usd(CoinbaseDepositOperation.minimumPurchaseUSD).converting(to: rate).value
        return micros(roundedUp(minimum, places: minorDigits))
    }

    /// The USD order for a top-up of `topUpMicros` in `rate`'s currency, rounded up to the cent so
    /// what lands is never less than the plan counted on.
    static func topUpOrderUSD(topUpMicros: Int64, rate: Rate) -> Decimal {
        let native = FiatAmount(value: Decimal(topUpMicros) / 1_000_000, currency: rate.currency)
        return roundedUp(native.convertingToUSD(rate: rate).value, places: 2)
    }

    private static func roundedUp(_ value: Decimal, places: Int) -> Decimal {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, places, .up)
        return rounded
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
                // Any top-up still on its way stays in the Dollars balance.
                fundingStore.clearPendingTopUp(for: requestID)
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
        isSubmitting = true
        defer { isSubmitting = false }
        if let outcome = await refetchIfNeeded() { return outcome }
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

    /// After a payment whose outcome isn't known, reads the intent ID again first. Returns the
    /// outcome to stop on, or nil to carry on paying.
    private func refetchIfNeeded() async -> Outcome? {
        guard needsRefetch else { return nil }
        switch await prepare() {
        case .ready: return nil
        case .nothingToPay where hasPaidCollection:
            // ALREADY_PAID: the attempt whose outcome was unknown landed, so don't pay again.
            return .success
        case .nothingToPay, .closed, .failed, .noBalance, .fundedByTopUp: return .failed
        }
    }

    // MARK: - Top-up -

    /// What the sheet's Add button does: adds `topUpMicros` of Dollars with Apple Pay, the amount
    /// the button showed, then funds and pays as soon as the Dollars land, with no second
    /// confirmation. A top-up this payment already ordered is waited on and never ordered again.
    /// Swaps an earlier attempt kept settle first, and nothing is ordered while one hasn't. When
    /// the balances read then need a different top-up, or none can be planned, nothing is ordered
    /// and the sheet shows the new short state.
    func addAndPay(topUpMicros: Int64) async -> Outcome {
        guard fundsCollection else { return .failed }
        return await joiningTopUpRun { [self] in await runAddAndPay(topUpMicros: topUpMicros) } ?? .failed
    }

    private func runAddAndPay(topUpMicros: Int64) async -> Outcome {
        if let outcome = await refetchIfNeeded() { return outcome }

        if let pending = fundingStore.pendingTopUp(for: requestID),
           let outcome = await finish(pending) {
            return outcome
        }

        guard let request, let payable, let fiat = payableFiat(payable, of: request),
              let rate = ratesController.rate(for: fiat.currency) else {
            showSendError()
            return .failed
        }
        // Checked before Apple Pay opens, so a payment the limit stops charges nothing.
        guard !exceedsSendLimit(fiat) else { return .failed }
        // A swap an earlier attempt kept may still land its Dollars, and one the server holds
        // unfunded is funded now, so each settles before the top-up is sized or its baseline read;
        // otherwise the user pays for money on its way.
        // The sheet closing during that wait stops the run: nothing is paid or ordered, and no
        // dialog shows over what's on screen now.
        switch await fundingExecutor.settleKeptSwaps(for: requestID, currency: fiat.currency) {
        case .nothingKept:
            break
        case .settled:
            guard !Task.isCancelled else { return .failed }
        case .pending:
            needsRefetch = true
            if !Task.isCancelled { showConversionPending() }
            return .failed
        case .failed:
            needsRefetch = true
            if !Task.isCancelled { showSendError() }
            return .failed
        }
        let baselineUSD: Decimal
        do {
            baselineUSD = try await topUpper.dollarsBalance()
        } catch {
            showSendError()
            return .failed
        }
        guard let plan = fundingPlan else {
            showInsufficientFunds(shortfall: nil)
            return .failed
        }
        // The balances cover it now, so the payment the button named runs without adding money.
        guard plan.topUpMicros > 0 else { return await submitFundedCollection(afterTopUp: false) }
        guard plan.topUpMicros == topUpMicros else { return .short }

        let amountUSD = Self.topUpOrderUSD(topUpMicros: plan.topUpMicros, rate: rate)
        let orderRef = topUpper.makeOrderRef()
        // Written before Apple Pay opens, so an attempt that dies mid-order leaves it behind.
        fundingStore.setPendingTopUp(
            .init(
                orderRef: orderRef,
                amountUSD: amountUSD,
                baselineUSD: baselineUSD,
                placedAt: clock(),
                authorized: false,
                payingCurrency: plan.payingCurrency
            ),
            for: requestID
        )
        let order = await topUpper.order(amountUSD: amountUSD, orderRef: orderRef) { [fundingStore, requestID] in
            fundingStore.markTopUpAuthorized(for: requestID)
        }
        switch order {
        case .notCharged(let reason):
            fundingStore.clearPendingTopUp(for: requestID)
            showTopUpNotCharged(reason)
            return .failed
        case .charged, .mayDeliver:
            fundingStore.markTopUpAuthorized(for: requestID)
            guard let pending = fundingStore.pendingTopUp(for: requestID) else { return .failed }
            return await finish(pending) ?? .failed
        }
    }

    /// Whether a top-up this payment ordered hasn't been seen landing yet, or one is running.
    var hasPendingTopUp: Bool {
        topUpRun != nil || fundingStore.pendingTopUp(for: requestID) != nil
    }

    /// Called as the sheet opens, before its first frame: a top-up still to pick up opens it on
    /// "Finishing Payment". ``resumePendingTopUp()`` ends that, whatever it finds.
    func sheetWillOpen() {
        isPickingUp = fundsCollection && hasPendingTopUp
    }

    /// Picks up a top-up an earlier attempt ordered, as the sheet opens after a relaunch: waits for
    /// its Dollars, then funds and pays. Returns nil when there's none to pick up, or when it
    /// turns out to have charged nothing, leaving the sheet on the state the balances give.
    func resumePendingTopUp() async -> Outcome? {
        defer { isPickingUp = false }
        guard fundsCollection, hasPendingTopUp else { return nil }
        return await joiningTopUpRun { [self] in
            if let outcome = await refetchIfNeeded() { return outcome }
            guard let pending = fundingStore.pendingTopUp(for: requestID) else { return nil }
            return await finish(pending)
        }
    }

    /// The top-up running now. A sheet opened again while an earlier one's run is still going, or
    /// a second tap, waits on it rather than starting another that could pay a second time.
    private var topUpRun: Task<Outcome?, Never>?

    private func joiningTopUpRun(_ body: @escaping @MainActor () async -> Outcome?) async -> Outcome? {
        if let topUpRun { return await topUpRun.value }
        let run = Task { await body() }
        topUpRun = run
        defer { topUpRun = nil }
        return await withTaskCancellationHandler { await run.value } onCancel: { run.cancel() }
    }

    /// "Finishing Payment": waits for `pending`'s Dollars, then funds and pays from the balances
    /// as they are then, in the currency picked this visit, else the one the top-up was planned
    /// for. Returns nil when the record cleared with no Dollars seen: that top-up charged nothing,
    /// so nothing is paid without the viewer asking. Returns `.short`, paying nothing, when that
    /// currency can't be paid in any more.
    private func finish(_ pending: CollectionFundingStore.PendingTopUp) async -> Outcome? {
        // A relaunch loses the visit's pick; the record keeps the currency planned before Apple Pay.
        if pickedCurrency == nil, let recorded = pending.payingCurrency {
            pickedCurrency = try? PublicKey(base58: recorded)
        }
        isFinishing = true
        defer { isFinishing = false }
        switch await settle(pending) {
        case .stopped: return .failed
        case .cleared: return nil
        case .landed:
            // The sheet closed as the Dollars landed: they stay, and the next attempt pays from them.
            guard !Task.isCancelled else { return .failed }
            // The plan falls back to another currency only when the asked one can't be named; the
            // sheet then shows that plan rather than paying in a currency nobody picked.
            if let asked = pickedCurrency?.base58, let plan = fundingPlan, plan.payingCurrency != asked {
                return .short
            }
            return await submitFundedCollection(afterTopUp: true)
        }
    }

    private enum Settlement {
        /// The Dollars were seen and the record cleared.
        case landed
        /// The record cleared with no Dollars seen: the order charged nothing.
        case cleared
        /// Still waiting, or the wait was cut short; the record stays.
        case stopped
    }

    /// Waits for `pending`'s Dollars and returns whether the payment can go on. Its record clears
    /// the moment they're seen, before any conversion or pay spends them.
    ///
    /// One Apple Pay never reported authorized charged nothing unless the app died in the moment
    /// between the two; it is waited on for at most the settlement window from when it was placed,
    /// then counted as failed. One that was authorized stays until its Dollars are seen.
    private func settle(_ pending: CollectionFundingStore.PendingTopUp) async -> Settlement {
        let target = CollectionTopUpTarget.target(baselineUSD: pending.baselineUSD, amountUSD: pending.amountUSD)
        if !pending.authorized {
            let landed: Bool
            if clock().timeIntervalSince(pending.placedAt) < Self.settlementSeconds {
                landed = await topUpper.awaitDollars(reaching: target)
                // A wait cut short, say by the sheet closing, decides nothing.
                if !landed, Task.isCancelled { return .stopped }
            } else {
                landed = ((try? await topUpper.dollarsBalance()) ?? 0) >= target
            }
            fundingStore.clearPendingTopUp(for: requestID)
            return landed ? .landed : .cleared
        }
        guard await topUpper.awaitDollars(reaching: target) else {
            if !Task.isCancelled { showMoneyStillOnItsWay() }
            return .stopped
        }
        fundingStore.clearPendingTopUp(for: requestID)
        return .landed
    }

    private static var settlementSeconds: TimeInterval {
        let (seconds, attoseconds) = AddMoneyTiming.settlementTimeout.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }

    /// Clears a pending top-up whose Dollars the balance already shows, without waiting.
    private func clearLandedTopUp() async {
        guard let pending = fundingStore.pendingTopUp(for: requestID), pending.authorized,
              let dollars = try? await topUpper.dollarsBalance(),
              dollars >= CollectionTopUpTarget.target(baselineUSD: pending.baselineUSD, amountUSD: pending.amountUSD)
        else { return }
        fundingStore.clearPendingTopUp(for: requestID)
    }

    /// Converts what the plan needs into the paying currency, each swap settled before the next,
    /// then pays once from it. Funding runs before the funds gate because a paying currency held
    /// at zero can't be priced there. `afterTopUp` is set once Dollars this attempt added have
    /// landed; a plan still short then asks again rather than ordering more.
    private func submitFundedCollection(afterTopUp: Bool = false) async -> Outcome {
        if !afterTopUp { await clearLandedTopUp() }
        guard let request, let payable, let creator = request.creator,
              let intentID, let intentKey = try? PublicKey(intentID),
              let chatID = request.chatID,
              let fiat = payableFiat(payable, of: request) else {
            showSendError()
            return .failed
        }
        guard !exceedsSendLimit(fiat) else { return .failed }

        switch await fundingExecutor.fund(requestID, currency: fiat.currency, plan: { self.fundingPlan }) {
        case .funded:
            break
        case .short:
            // The sheet shows the short state for the plan as read now; a top-up waits for the
            // user to confirm it. A plan that can't be built at all keeps today's dialog.
            guard fundingPlan != nil else {
                showInsufficientFunds(shortfall: fundingShortfall(in: fiat.currency))
                return .failed
            }
            return .short
        case .failed:
            // Swaps that landed stay converted; the retry reads the intent ID again before funding.
            needsRefetch = true
            showSendError()
            return .failed
        case .pending:
            // The swap keeps its id; the retry waits on it before converting anything more.
            needsRefetch = true
            showConversionPending()
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

        guard !exceedsSendLimit(amount.nativeAmount) else { return .failed }

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

    private func showTopUpNotCharged(_ reason: CollectionTopUpOrder.NotCharged) {
        switch reason {
        case .cancelled:
            break
        case .timedOut:
            session.dialogItem = .info(
                title: String(localized: "Purchase Timed Out", comment: "Title shown when Apple Pay wasn't authorized in time while adding money for a payment"),
                subtitle: String(localized: "Purchases must be authorized within 60 seconds", comment: "Body shown when Apple Pay wasn't authorized in time while adding money for a payment")
            )
        case .rejected(let title, let subtitle):
            session.dialogItem = .error(title: title, subtitle: subtitle)
        case .failed:
            session.dialogItem = .error(
                title: String(localized: "Something Went Wrong", comment: "Title shown when adding money for a payment failed before anything was charged"),
                subtitle: String(localized: "Please try again later", comment: "Body shown when adding money for a payment failed before anything was charged")
            )
        }
    }

    /// No frame draws this state; the copy says what the spec asks for. The record stays, so the
    /// next tap waits on the same order again instead of placing another.
    private func showMoneyStillOnItsWay() {
        session.dialogItem = .info(
            title: String(localized: "Money Still on Its Way", comment: "Title shown when money added with Apple Pay for a payment hasn't arrived yet"),
            subtitle: String(localized: "The money you added hasn’t arrived yet. Try again shortly and you won’t be charged again.", comment: "Body shown when money added with Apple Pay for a payment hasn't arrived yet")
        )
    }

    /// Whether `fiat` is over the next-transaction send limit, showing the limit dialog when it is.
    private func exceedsSendLimit(_ fiat: FiatAmount) -> Bool {
        let sendLimit = session.sendLimitFor(currency: fiat.currency) ?? .zero
        guard fiat.value > sendLimit.nextTransaction.value else { return false }
        session.dialogItem = .error(
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily"
        )
        return true
    }

    /// No frame draws this state; the copy says what the spec asks for.
    private func showConversionPending() {
        session.dialogItem = .info(
            title: String(localized: "Conversion Pending", comment: "Title shown when a currency conversion for a payment hasn't settled yet"),
            subtitle: String(localized: "Your conversion is still pending. Try again shortly.", comment: "Body shown when a currency conversion for a payment hasn't settled yet")
        )
    }

    private func showSendError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't complete the transfer. Please try again."
        )
    }
}
