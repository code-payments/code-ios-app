//
//  SendAmountViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.send-amount")

@Observable
final class SendAmountViewModel {

    /// Result of a send attempt. `.success` and `.recipientNotFound` both dismiss
    /// the sheet back to the chat; `.failed` keeps it on amount entry. Error copy
    /// is surfaced internally via `session.dialogItem`.
    enum SendOutcome: Equatable {
        case success
        case recipientNotFound
        case failed
    }

    enum Error: Swift.Error {
        /// The send reached submission with nothing to spend from — no balance
        /// resolved, or the resolved balance can't price the entered amount.
        case noSpendableBalance
    }

    var enteredAmount: String = ""

    var depositMint: PublicKey?

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored let conversationController: ConversationController
    @ObservationIgnored let sender: any DirectSending
    @ObservationIgnored let resolver: any RecipientResolving
    @ObservationIgnored let target: SendTarget
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let amountValidator = AmountValidator()

    /// The tip recipient's profile, which carries the fee they charge to open a
    /// DM. Nil for a contact send, and until a fetch lands for a recipient the
    /// cache didn't already hold.
    private(set) var recipientProfile: Profile?

    /// The mint this flow opened for, replayed by the re-resolve below.
    @ObservationIgnored private let initialMint: PublicKey?

    private(set) var selectedBalance: ExchangedBalance?

    /// Cached after the first successful resolve so a retried send (e.g. after a
    /// transient send failure) skips the round-trip.
    private var resolvedRecipient: PublicKey?

    /// A verified rate proof warmed while the send UI is on screen (see
    /// `prewarmVerifiedRate()`) so `submit` doesn't race a cold cache at the
    /// moment the user commits. Consumed by `prepareSubmission`; invalidated on
    /// token change and re-checked for staleness before use.
    private var prewarmedState: VerifiedState?

    /// Amount validity only — never gated on the recipient. A red subtitle in
    /// `EnterAmountView` (driven by `!canSend`) therefore means over-limit, not
    /// "recipient unresolved"; resolution happens on the Send tap instead.
    var canSend: Bool {
        guard let enteredFiat else { return false }
        return enteredFiat.onChainAmount.quarks > 0
    }

    /// True when this send would be the payment that opens the tip DM — the one
    /// the recipient's fee buys. Drives the swipe label and which floor applies.
    /// False for a contact send and for a thread that already exists.
    var opensTipDM: Bool {
        guard case .tip(let recipient) = target else { return false }
        // The same rule `ConversationScreen.chatExists` draws: a tip DM's id is
        // derived locally, so the feed holding it is what says the chat is real.
        return conversationController.conversation(
            withID: .tipDm(between: session.userID, and: recipient.userID)
        ) == nil
    }

    /// The floor this entry has to clear when the amount is priced in
    /// `currency`, or nil when it has none.
    ///
    /// A fee the recipient sets buys the conversation, so it applies to exactly
    /// one payment: the tip that opens the DM. Past that the tip card falls back
    /// to the regional minimum every tip carries, and an in-chat send — a plain
    /// send into an open thread — carries no floor at all.
    func tipFloor(in currency: CurrencyCode) -> TipFloor? {
        guard case .tip(let recipient) = target else { return nil }
        let presets = session.userFlags?.tipPresets(for: currency)
        guard opensTipDM else {
            switch recipient.origin {
            case .chat:    return nil
            case .tipcard: return .systemMinimum(presets: presets)
            }
        }
        return .toOpenDM(
            recipientFee: recipientProfile?.minDmChatInitFee,
            presets: presets,
            in: currency,
            rates: ratesController.cachedRates
        )
    }

    /// The tip floor for the display currency, stated under the amount so a
    /// rejection is the exception rather than the flow. Nil when this entry
    /// carries no floor, and until the server's presets arrive.
    var tipMinimum: FiatAmount? {
        tipFloor(in: ratesController.balanceCurrency)?.displayed
    }

    /// The keypad buffer parsed to a positive amount, or nil.
    private var validatedEntered: Decimal? {
        guard let amount = amountValidator.validate(enteredAmount), amount > 0 else { return nil }
        return amount
    }

    private var enteredFiat: ExchangedFiat? {
        guard let amount = validatedEntered,
              let selectedBalance else { return nil }
        return selectedBalance.enteredFiat(
            for: amount,
            rate: ratesController.rateForBalanceCurrency()
        )
    }

    // MARK: - Init -

    init(
        sessionContainer: SessionContainer,
        target: SendTarget,
        mint: PublicKey? = nil,
        sender: (any DirectSending)? = nil,
        resolver: (any RecipientResolving)? = nil
    ) {
        let session          = sessionContainer.session
        let ratesController  = sessionContainer.ratesController
        let resolved         = ratesController.resolveInitialBalance(mint: mint, session: session)

        self.session         = session
        self.ratesController = ratesController
        self.conversationController = sessionContainer.conversationController
        self.flipClient      = sessionContainer.flipClient
        self.sender          = sender ?? session
        self.resolver        = resolver ?? session
        self.target          = target
        self.initialMint     = mint
        self.selectedBalance = resolved

        if case .tip(let recipient) = target {
            self.recipientProfile = session.cachedUserProfile(for: recipient.userID)
            if recipientProfile == nil {
                loadRecipientProfile(recipient.userID)
            }
        }

        if let resolved {
            syncGlobalTokenSelection(to: resolved)
        } else {
            observeBalancesForInitialResolve()
        }
    }

    /// Fills in the recipient's fee for the in-chat entry, whose counterpart
    /// arrives from the conversation rather than a resolved tip card (which has
    /// already cached one). Best effort: a miss leaves the entry on the regional
    /// minimum, with the server still the authority on the swipe.
    private func loadRecipientProfile(_ userID: UserID) {
        Task { [weak self] in
            guard let self else { return }
            guard let profile = try? await flipClient.fetchProfile(
                userID: userID,
                owner: session.ownerKeyPair
            ) else { return }
            session.cacheUserProfile(profile, for: userID)
            recipientProfile = profile
        }
    }

    // MARK: - Balance resolution -

    /// Re-runs the initial resolve when the balance list or display rate
    /// changes, until it lands on a balance.
    ///
    /// A tip deep link builds this view model at the coldest point of a cold
    /// launch — before balances have loaded and before the rate stream has
    /// delivered anything — so the initial resolve can legitimately come up
    /// empty. Without this the nil snapshot sticks for the life of the flow:
    /// the token pill renders as a bare chevron and every submission fails the
    /// `selectedBalance` guard in `submit`. Re-arms after each change since
    /// `withObservationTracking` is one-shot, and stops once a balance lands or
    /// the user picks one themselves.
    private func observeBalancesForInitialResolve() {
        withObservationTracking {
            _ = session.balances
            _ = ratesController.rateForBalanceCurrency()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, selectedBalance == nil else { return }
                guard let resolved = ratesController.resolveInitialBalance(
                    mint: initialMint,
                    session: session
                ) else {
                    observeBalancesForInitialResolve()
                    return
                }
                selectedBalance = resolved
                syncGlobalTokenSelection(to: resolved)
            }
        }
    }

    private func syncGlobalTokenSelection(to balance: ExchangedBalance) {
        guard ratesController.selectedTokenMint != balance.stored.mint else { return }
        ratesController.selectToken(balance.stored.mint)
    }

    // MARK: - Action -

    /// Validates the amount locally, resolves the recipient on the Send tap
    /// (retrying a transient network failure), then submits. The control owns
    /// the loading/checkmark state; this returns only where to go next.
    @discardableResult
    func sendAction() async -> SendOutcome {
        guard let entered = validatedEntered else { return .failed }
        return await submit(entered: entered)
    }

    /// The floor `entered` falls short of, or nil when it clears — or when no
    /// floor applies. The silent half of ``enforceTipMinimum(entered:)``, for
    /// deciding which amounts to offer rather than judging one.
    func unmetTipMinimum(entered: Decimal) -> TipFloor? {
        guard let exchangedFiat = selectedBalance?.enteredFiat(
            for: entered,
            rate: ratesController.rateForBalanceCurrency()
        ), let floor = tipFloor(in: exchangedFiat.nativeAmount.currency) else {
            // No floor (or no balance yet) — the server remains the authority.
            return nil
        }
        return floor.isMet(by: exchangedFiat) ? nil : floor
    }

    /// Whether `entered` clears this entry's tip floor, surfacing the minimum
    /// dialog when it doesn't. Contact sends always pass. The one gate both the
    /// swipe path and the custom-amount entry use.
    func enforceTipMinimum(entered: Decimal) -> Bool {
        guard let floor = unmetTipMinimum(entered: entered) else { return true }
        // Grey rather than red: the entry is under a stated floor, not a
        // failure, and the floor is already on screen (node 9553:20236).
        session.dialogItem = .info(
            title: "\(floor.displayed.formatted()) Minimum Tip",
            subtitle: "Please enter a higher amount"
        )
        return false
    }

    /// The full submission path for an already-validated amount in the display
    /// currency — the entry point the tip sheet's preset chips use directly.
    @discardableResult
    func submit(entered: Decimal) async -> SendOutcome {
        guard let selectedBalance,
              let exchangedFiat = selectedBalance.enteredFiat(
                for: entered,
                rate: ratesController.rateForBalanceCurrency()
              ) else {
            // No RPC and no thrown error, so this is invisible unless reported:
            // the swipe control just resets its knob and the user sees nothing.
            ErrorReporting.captureError(
                Error.noSpendableBalance,
                reason: "No spendable balance at send submission",
                metadata: [
                    "target": targetLogID,
                    "mint": selectedBalance?.stored.mint.base58 ?? "unresolved",
                ]
            )
            session.dialogItem = .error(
                title: "Balance Unavailable",
                subtitle: "We couldn't load your balance. Please try again."
            )
            return .failed
        }

        guard enforceTipMinimum(entered: entered) else { return .failed }

        switch session.hasSufficientFunds(for: exchangedFiat) {
        case .insufficient(let shortfall):
            if let shortfall {
                showYoureShortError(amount: shortfall)
            } else {
                showInsufficientBalanceError()
            }
            return .failed

        case .sufficient:
            let recipient: PublicKey
            switch await resolveRecipient() {
            case .resolved(let owner):
                recipient = owner
            case .notFound:
                showRecipientNotFoundError()
                return .recipientNotFound
            case .failed:
                showResolveFailedError()
                return .failed
            }

            guard let (amountToSend, pinnedState) = await prepareSubmission(entered: entered) else {
                // A nil here is a silent local cache miss (no RPC, no thrown error), so
                // it would otherwise be invisible to reporting. Record a breadcrumb at
                // `.info` — the classified level of `exchangeRateUnavailable` — so a
                // spike in cold-start rate races is visible without paging Slack.
                ErrorReporting.captureError(
                    RatesController.Error.exchangeRateUnavailable,
                    reason: "No fresh rate at send submission",
                    metadata: [
                        "target": targetLogID,
                        "mint": selectedBalance.stored.mint.base58,
                    ]
                )
                session.dialogItem = .error(
                    title: "Rate Unavailable",
                    subtitle: "Couldn't get a fresh rate. Please try again."
                )
                return .failed
            }

            let sendLimit = session.sendLimitFor(currency: amountToSend.nativeAmount.currency) ?? .zero
            guard amountToSend.nativeAmount.value <= sendLimit.nextTransaction.value else {
                logger.info("Send rejected: amount exceeds limit", metadata: [
                    "amount": "\(amountToSend.nativeAmount.formatted())",
                    "next_tx": "\(sendLimit.nextTransaction.value)",
                    "currency": "\(amountToSend.nativeAmount.currency)",
                ])
                showLimitsError()
                return .failed
            }

            // Only a tip card payment is a tip — the same line the activity feed
            // draws, from `ChatMetadata.TipDmPayment.Location`. Both the scanned
            // tipcard flow and the Send Cash action inside a tip thread submit
            // here, and the latter reports as a plain cash send.
            let isTip = if case .tip(let recipient) = target { recipient.origin == .tipcard } else { false }
            let transferEvent: Analytics.TransferEvent = isTip ? .sentTip : .sentCash

            do {
                try await sender.send(
                    amount: amountToSend,
                    verifiedState: pinnedState,
                    to: recipient,
                    chat: chatPaymentMetadata()
                )
                Analytics.transfer(event: transferEvent, exchangedFiat: amountToSend, grabTime: nil, successful: true, error: nil)
                return .success
            } catch {
                Analytics.transfer(event: transferEvent, exchangedFiat: amountToSend, grabTime: nil, successful: false, error: error)
                showSendError()
                return .failed
            }
        }
    }

    /// Chat context for posting this payment into the recipient's DM. Contact
    /// sends require the contact's server-issued chat ID and the sender's own
    /// payment-linked phone — without both, the payment submits without chat
    /// metadata. Tip sends derive the canonical tip-DM chat ID locally.
    private func chatPaymentMetadata() -> ChatPaymentMetadata? {
        switch target {
        case .contact(let contact):
            guard let dmChatID = contact.dmChatID,
                  let ownPhone = session.profile?.phone else {
                return nil
            }
            return .contactDm(
                chatID: ConversationID(data: dmChatID),
                sourcePhoneE164: ownPhone.e164,
                destinationPhoneE164: contact.phoneE164
            )
        case .tip(let recipient):
            return .tipDm(
                chatID: .tipDm(between: session.userID, and: recipient.userID),
                origin: recipient.origin
            )
        }
    }

    // MARK: - Recipient resolution -

    private enum RecipientResolution {
        case resolved(PublicKey)
        case notFound
        case failed
    }

    /// Resolves the recipient, retrying once on a transient network error. A
    /// successful resolution is cached so a retried send skips the round-trip.
    private func resolveRecipient() async -> RecipientResolution {
        if let resolvedRecipient {
            return .resolved(resolvedRecipient)
        }
        for attempt in 0..<2 {
            do {
                let owner: PublicKey
                switch target {
                case .contact(let contact):
                    owner = try await resolver.resolveContact(e164: contact.phoneE164)
                case .tip(let recipient):
                    owner = try await resolver.resolveUserID(recipient.userID)
                }
                resolvedRecipient = owner
                return .resolved(owner)
            } catch ErrorResolve.notFound {
                logger.info("Recipient not on Flipcash", metadata: ["target": "\(targetLogID)"])
                return .notFound
            } catch ErrorResolve.transportFailure where attempt == 0 {
                continue
            } catch {
                logger.error("Recipient resolve failed", metadata: ["target": "\(targetLogID)", "error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Recipient resolve failed", userFacing: true)
                return .failed
            }
        }
        return .failed
    }

    /// Stable identifier for the target in log metadata.
    private var targetLogID: String {
        switch target {
        case .contact(let contact): contact.contactId
        case .tip(let recipient):   recipient.userID.uuidString
        }
    }

    /// Returns nil when no fresh pin is cached; otherwise the amount + pin
    /// computed against that same pin so quarks can't drift from the proof.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let entered = validatedEntered else { return nil }
        return await prepareSubmission(entered: entered)
    }

    private func prepareSubmission(entered: Decimal) async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let selectedBalance else { return nil }
        let mint = selectedBalance.stored.mint

        // A tip deep link opens on a cold foreground, racing the rate stream/warm-load
        // (a sibling of the #545 recipient-resolve race). For tips, poll for a fresh
        // pinned state rather than failing the first time the cache is momentarily empty
        // or holding a stale warm-loaded proof. In-app contact sends run warm, so they
        // keep the single-shot read.
        let pinnedState: VerifiedState?
        switch target {
        case .tip:
            // Prefer a proof warmed while the sheet was on screen; fall back to a
            // fresh poll if the prewarm never finished or has since gone stale.
            if let prewarmedState, !prewarmedState.isStale {
                pinnedState = prewarmedState
            } else {
                pinnedState = await ratesController.awaitPinnedState(
                    for: ratesController.balanceCurrency,
                    mint: mint
                )
            }
        case .contact:
            pinnedState = await ratesController.currentPinnedState(
                for: ratesController.balanceCurrency,
                mint: mint
            )
        }
        guard let pin = pinnedState else { return nil }

        let nativeEntered = FiatAmount(value: entered, currency: pin.rate.currency)

        if mint == .usdf {
            return (ExchangedFiat(nativeAmount: nativeEntered, rate: pin.rate), pin)
        }

        let balance = session.balance(for: mint)
        guard let pinnedSupply = pin.supplyFromBonding,
              let amount = ExchangedFiat.compute(
                fromEntered: nativeEntered,
                rate: pin.rate,
                mint: mint,
                supplyQuarks: pinnedSupply,
                balance: balance.map(\.usdf),
                tokenBalanceQuarks: balance?.quarks
              ) else { return nil }

        return (amount, pin)
    }

    /// Warms the verified rate proof while the send UI is on screen so `submit`
    /// doesn't race a cold cache at the moment the user commits — the wait overlaps
    /// the time the user spends reading the sheet instead of stalling the swipe.
    /// Safe to call fire-and-forget: `prepareSubmission` falls back to a fresh poll
    /// if this hasn't finished or the cached proof has since gone stale.
    func prewarmVerifiedRate() async {
        guard let mint = selectedBalance?.stored.mint else { return }
        prewarmedState = await ratesController.awaitPinnedState(
            for: ratesController.balanceCurrency,
            mint: mint
        )
    }

    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        ratesController.selectToken(exchangedBalance.stored.mint)
        enteredAmount = ""
        // The warmed proof was for the previous token (and a launchpad mint also
        // needs its own reserve proof) — drop it so submission re-warms/polls.
        prewarmedState = nil
    }

    // MARK: - Navigation -

    private func presentDeposit() {
        depositMint = selectedBalance?.stored.mint
        if let depositMint {
            Analytics.tokenInfoOpened(from: .openedFromSend, mint: depositMint)
        }
    }

    // MARK: - Errors -

    private func showInsufficientBalanceError() {
        session.dialogItem = .error(
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount"
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showYoureShortError(amount: ExchangedFiat) {
        session.dialogItem = .error(
            title: "You're \(amount.nativeAmount.formatted()) Short",
            subtitle: "Add more cash, or try again with a lower amount"
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showLimitsError() {
        session.dialogItem = .error(
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily"
        )
    }

    private func showSendError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't complete the transfer. Please try again."
        )
    }

    private func showRecipientNotFoundError() {
        session.dialogItem = .error(
            title: "Not on Flipcash",
            subtitle: "This contact isn't on Flipcash. Pick someone else to send cash."
        )
    }

    private func showResolveFailedError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't reach the network. Please try again."
        )
    }
}
