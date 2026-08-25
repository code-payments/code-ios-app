//
//  TipFlow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.tip-flow")

/// Session-scoped orchestrator for sending a tip. Entered from a scanned
/// tipcode or a tipcard link, it gates the entry (profile, balance), resolves
/// the recipient, drives the tipcard overlay + Send a Tip sheet, and submits
/// through the direct-send path.
@Observable
final class TipFlow {

    /// Whether the Send a Tip sheet is up. Writing false through the binding
    /// (a swipe-down) cancels the whole flow.
    var isSheetPresented = false

    /// The custom amount chosen through the "…" chip, occupying the fourth
    /// slot until the flow resets.
    private(set) var customAmount: Decimal?

    /// Which chip is selected.
    var selection: TipSelection? = nil

    /// The direct-send engine for the presented recipient. Owns the target,
    /// the selected balance, and the full submission path (minimum, funds,
    /// pin, limits). Non-nil exactly while a tip is being composed.
    private(set) var submission: SendAmountViewModel?

    /// A recipient held while the user creates a profile; resumed by
    /// ``resumeAfterProfileCreation()`` once `isTippable` flips true.
    @ObservationIgnored private(set) var pendingUserID: UserID?

    @ObservationIgnored private var prepTask: Task<Void, Never>?

    /// Keeps the keyboard down while a tipcard is being routed to. A tipcard
    /// link is commonly followed from a chat the user left focused, and the
    /// card is an overlay — it never displaces the composer that owns the
    /// keyboard, so the keyboard has to be taken away deliberately.
    @ObservationIgnored private let keyboard = KeyboardSuppressor()

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let sessionContainer: SessionContainer
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let router: AppRouter

    init(sessionContainer: SessionContainer) {
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.ratesController  = sessionContainer.ratesController
        self.flipClient       = sessionContainer.flipClient
        self.router           = sessionContainer.appRouter
    }

    // MARK: - Presets -

    /// The preset tiers for the display currency, USD row fallback.
    var presets: UserFlags.TipPresets? {
        session.userFlags?.tipPresets(for: ratesController.balanceCurrency)
    }

    /// The fiat amount a chip stands for, in the display currency.
    func amount(for selection: TipSelection?) -> Decimal? {
        switch selection {
        case .low:    presets?.low
        case .medium: presets?.medium
        case .high:   presets?.high
        case .custom: customAmount
        case .none:   nil
        }
    }

    /// The fiat amount the current selection stands for.
    var selectedAmount: Decimal? {
        amount(for: selection)
    }

    // MARK: - Entry -

    /// Handles a scanned or deeplinked tipcode. Gates in order: own-id codes
    /// (routed to the user's own tip card), then a tippable profile (held +
    /// profile creation presented).
    /// The card always shows for a tippable recipient; the giveable-balance gate
    /// is deferred to ``present(_:)``, where it blocks the Send a Tip sheet
    /// (surfacing the Add Money / Discover dialog) without hiding the card.
    func begin(userID: UserID) {
        // Tipping yourself is a payment no-op, so there's no flow to start from
        // your own code — show the user their own tip card rather than swallow
        // the scan or tap. `showOwnTipCard()` absorbs the repeat calls the
        // per-frame scanner makes until the camera tears down.
        guard userID != session.userID else {
            keyboard.suppress()
            router.showOwnTipCard()
            return
        }
        guard submission == nil, pendingUserID == nil, prepTask == nil else { return }
        // A dialog is already asking the user something (commonly this flow's
        // own balance gate) — don't churn it on every decoded camera frame.
        guard session.dialogItem == nil else { return }

        guard session.profile?.isTippable == true else {
            pendingUserID = userID
            logger.info("Tip held for profile creation", metadata: ["recipient": "\(userID)"])
            // Deliberately unsuppressed: profile creation focuses its name
            // field on appear, and that keyboard is wanted.
            router.present(.tips)
            return
        }

        keyboard.suppress()
        prepare(userID: userID)
    }

    /// Re-enters a held tip once the profile became tippable.
    func resumeAfterProfileCreation() {
        guard let pendingUserID, session.profile?.isTippable == true else { return }
        self.pendingUserID = nil
        router.dismissSheet()
        begin(userID: pendingUserID)
    }

    /// Drops a held recipient — the user backed out of profile creation.
    func abandonPendingTip() {
        pendingUserID = nil
    }

    /// Tears down the card, the sheet, and any in-flight preparation.
    /// Idempotent — safe from both the drag-dismissed card and the swiped-down
    /// sheet.
    func cancel() {
        prepTask?.cancel()
        prepTask = nil
        isSheetPresented = false
        submission = nil
        if case .tipcard = session.billState.bill {
            session.dismissCashBill(style: .slide)
        }
    }

    // MARK: - Recipient -

    private func prepare(userID: UserID) {
        prepTask = Task {
            defer { prepTask = nil }
            do {
                // The gRPC channel is often still connecting when a tipcard deep
                // link fires on a cold foreground (it races `warmUpChannel()`),
                // so the first resolve fails `.unavailable`; a just-made-tippable
                // recipient's destination may also not have propagated yet.
                // Retry both transient conditions before surfacing a hard error —
                // mirroring the cash-link claim path — so the user isn't told to
                // "try again" for a tap that a second attempt would have resolved.
                // A definitive `.denied`/anomaly is not retried.
                let resolved = try await Task.retry(
                    maxAttempts: 3,
                    delay: .milliseconds(500),
                    shouldRetry: { error in
                        if let error = error as? ErrorResolve { return error == .notFound || error.isRetryable }
                        if let error = error as? ErrorFetchProfile { return error.isRetryable }
                        return false
                    }
                ) {
                    async let profile = flipClient.fetchProfile(userID: userID, owner: session.ownerKeyPair)
                    async let destination = flipClient.resolveUserID(userID, owner: session.ownerKeyPair)
                    // The destination is re-resolved (and cached) by the send
                    // itself; here it only proves the user can be paid at all.
                    _ = try await destination
                    return try await profile
                }
                session.cacheUserProfile(resolved, for: userID)
                let recipient = TipRecipient(
                    userID: userID,
                    displayName: resolved.displayName ?? "",
                    origin: .tipcard
                )
                guard !Task.isCancelled else { return }
                present(recipient)
                await loadAvatar(for: recipient, picture: resolved.profilePicture)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to prepare tip recipient", metadata: [
                    "recipient": "\(userID)",
                    "error": "\(error)",
                ])
                ErrorReporting.captureError(error, reason: "Failed to prepare tip recipient")
                session.dialogItem = .error(
                    title: "Tipcard Not Available",
                    subtitle: "This tipcard can't receive tips right now. Please try again."
                )
            }
        }
    }

    private func present(_ recipient: TipRecipient) {
        // The card is resolved and about to show, whether reached from a scan or
        // a deep link — the second step of the Scanned → Presented → Sent Tip funnel.
        Analytics.track(event: Analytics.TipCardEvent.presented)
        // Again, because the resolve above retries: a cold-foreground `.unavailable`
        // outlasts the window opened at `begin`, so the restore can win after it has
        // closed. The card is a focused modal and must never share the screen with a
        // keyboard, so it takes one down on the way up regardless.
        keyboard.suppress()
        selection = nil
        customAmount = nil
        submission = SendAmountViewModel(
            sessionContainer: sessionContainer,
            target: .tip(recipient)
        )

        // A tip deep link can beat the app's foreground stream refresh, so kick the
        // rate stream to reconnect now and warm the verified proof while the card
        // animates in and the user reads the sheet. This overlaps the rate wait with
        // on-screen time so the swipe submits instantly instead of racing a cold
        // cache; the submit-time poll in `prepareSubmission` remains the backstop.
        ratesController.ensureStreamConnected()
        Task { [weak self] in await self?.submission?.prewarmVerifiedRate() }

        session.billState = BillState(bill: .tipcard(
            codeData: TipCode.Payload(userID: recipient.userID).codeData(),
            name: recipient.displayName,
            avatar: nil
        ))
        session.presentationState = .visible(.pop)

        // The sheet follows once the card's pop has settled, mirroring the
        // received-cash valuation timing — but only if the balance gate clears.
        // A blocked gate surfaces its dialog and leaves the card up without the
        // sheet. `submission` is nilled by `cancel()`, so a card dismissed during
        // the delay never presents a stale sheet.
        Task { [weak self] in
            try? await Task.delay(milliseconds: 750)
            guard let self, submission != nil else { return }
            let rate = ratesController.rateForBalanceCurrency()
            if let dialog = giveCashGate(session: session, rate: rate, includingDollars: BetaFlags.shared.allowsDollarsGive)
                .blockingDialog(router: router, addMoneySource: .scanner, context: .sendTips)?
                .onDismiss(perform: { [weak self] in self?.cancel() }) {
                session.dialogItem = dialog
                return
            }
            isSheetPresented = true
        }
    }

    /// Fetches the recipient's avatar through the shared tip-avatar store —
    /// warming the same cache the conversation surfaces read — and re-renders
    /// the card with it. The card is already up, so a failure just leaves the
    /// placeholder.
    private func loadAvatar(for recipient: TipRecipient, picture: ProfilePicture?) async {
        let store = sessionContainer.tipAvatars
        await store.load(userID: recipient.userID, picture: picture)
        guard let data = store.data(for: recipient.userID),
              let avatar = UIImage(data: data),
              case .tipcard(let codeData, let name, _) = session.billState.bill else { return }
        session.billState.bill = .tipcard(codeData: codeData, name: name, avatar: avatar)
    }

    // MARK: - Amounts -

    /// Adopts a custom amount when it clears the tip minimum (the engine
    /// surfaces the minimum dialog when it doesn't) and selects it.
    func setCustomAmount(_ amount: Decimal) -> Bool {
        guard let submission, submission.enforceTipMinimum(entered: amount) else {
            return false
        }
        customAmount = amount
        selection = .custom
        return true
    }

    func selectCurrency(_ balance: ExchangedBalance) {
        submission?.selectCurrencyAction(exchangedBalance: balance)
        // Both the selection and the custom entry are cleared: the new token's
        // balance may not cover them, and its tip minimum is enforced afresh on
        // the next selection.
        selection = nil
        customAmount = nil
    }

    /// Whether `balance` holds at least the tip minimum, so the picker can
    /// disable tokens that can't fund even the smallest tip. No presets means
    /// the server remains the authority — every token stays enabled.
    func meetsMinimum(_ balance: ExchangedBalance) -> Bool {
        guard let presets else { return true }
        return presets.meetsMinimum(balance.exchangedFiat)
    }

    // MARK: - Submission -

    /// Thrown so the swipe control resets its knob without a success check.
    private struct TipDismissed: Error {}

    /// Submits the selected amount. On success, tears down the card + sheet
    /// and opens the new tip conversation.
    func swipeToTip() async throws {
        guard let submission, let amount = selectedAmount,
              case .tip(let recipient) = submission.target else {
            throw TipDismissed()
        }

        switch await submission.submit(entered: amount) {
        case .success:
            finish(recipient: recipient)
        case .recipientNotFound:
            cancel()
            throw TipDismissed()
        case .failed:
            throw TipDismissed()
        }
    }

    private func finish(recipient: TipRecipient) {
        isSheetPresented = false
        submission = nil
        if case .tipcard = session.billState.bill {
            session.dismissCashBill(style: .pop)
        }

        let chatID = ConversationID.tipDm(between: session.userID, and: recipient.userID)
        Task { [router] in
            try? await Task.delay(milliseconds: 600)
            // Open the post-tip chat with the keyboard up — the tip-specific
            // variant focuses the composer; ordinary opens stay closed.
            router.navigate(to: .tipConversationWithKeyboard(chatID))
        }
    }
}

// MARK: - TipSelection -

/// Which of the sheet's four amount chips is active.
enum TipSelection: String, Hashable {
    case low
    case medium
    case high
    case custom
}
