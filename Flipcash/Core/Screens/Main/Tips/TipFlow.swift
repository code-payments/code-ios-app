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
    /// ``resumeAfterProfileCreation()`` once `isTippable` flips true. Holds
    /// whichever identifier the entry carried — a scanned code's user id or a
    /// vanity link's handle.
    @ObservationIgnored private(set) var pendingRecipient: ProfileIdentifier?

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

    /// The fiat amount the current selection stands for, or nil when it no
    /// longer clears the tip floor — the recipient's fee resolves after the
    /// sheet is up, so a selection made before it landed can fall under it.
    var selectedAmount: Decimal? {
        guard let amount = amount(for: selection),
              submission?.unmetTipMinimum(entered: amount) == nil else {
            return nil
        }
        return amount
    }

    /// The preset tiers on offer. A tier below the floor this tip has to clear
    /// isn't offered: a chip never passes through the amount entry, so it would
    /// only be rejected on the swipe.
    var offeredTiers: [TipSelection] {
        [.low, .medium, .high].filter { tier in
            guard let amount = amount(for: tier) else { return true }
            return submission?.unmetTipMinimum(entered: amount) == nil
        }
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
            showOwnTipCard()
            return
        }
        begin(.userID(userID))
    }

    /// Handles a vanity tipcard link — `flipcash.com/<handle>`. The handle
    /// resolves to the same card a scanned code opens; the own-handle case is
    /// caught here when the local profile knows its handle, and again after the
    /// resolve when it doesn't.
    func begin(username: Username) {
        guard session.profile?.username != username else {
            showOwnTipCard()
            return
        }
        begin(.username(username))
    }

    private func begin(_ identifier: ProfileIdentifier) {
        guard submission == nil, pendingRecipient == nil, prepTask == nil else { return }
        // A dialog is already asking the user something (commonly this flow's
        // own balance gate) — don't churn it on every decoded camera frame.
        guard session.dialogItem == nil else { return }

        guard session.profile?.isTippable == true else {
            pendingRecipient = identifier
            logger.info("Tip held for profile creation", metadata: ["recipient": "\(identifier)"])
            // Deliberately unsuppressed: profile creation focuses its name
            // field on appear, and that keyboard is wanted.
            router.present(.tips)
            return
        }

        keyboard.suppress()
        prepare(identifier)
    }

    private func showOwnTipCard() {
        keyboard.suppress()
        router.showOwnTipCard()
    }

    /// Re-enters a held tip once the profile became tippable.
    func resumeAfterProfileCreation() {
        guard let pendingRecipient, session.profile?.isTippable == true else { return }
        self.pendingRecipient = nil
        router.dismissSheet()
        begin(pendingRecipient)
    }

    /// Drops a held recipient — the user backed out of profile creation.
    func abandonPendingTip() {
        pendingRecipient = nil
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

    /// Thrown when a handle resolved to a profile the server didn't stamp with
    /// a user id — a tip has nobody to pay without one. `fetchProfile` answers
    /// an unclaimed handle with `Profile.empty` rather than throwing, so this
    /// is the shape that case arrives in.
    private struct UnidentifiedRecipient: ServerError {
        var reportingLevel: ErrorReportingLevel { .info }
    }

    private func prepare(_ identifier: ProfileIdentifier) {
        // Whether the link named a handle rather than an id decides both the
        // retry policy below and which copy a failure gets.
        let handle: Username?
        switch identifier {
        case .userID:                 handle = nil
        case .username(let username): handle = username
        }

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
                        if let error = error as? ErrorResolve {
                            // `.notFound` is retried for an id only: there it means a
                            // just-made-tippable recipient whose destination hasn't
                            // propagated yet. For a handle it is the settled answer,
                            // so retrying only spends the backoff before saying so.
                            if error == .notFound { return handle == nil }
                            return error.isRetryable
                        }
                        if let error = error as? ErrorFetchProfile { return error.isRetryable }
                        return false
                    }
                ) {
                    async let profile = flipClient.fetchProfile(identifier, owner: session.ownerKeyPair)
                    async let destination = flipClient.resolve(identifier, owner: session.ownerKeyPair)
                    // The destination is re-resolved (and cached) by the send
                    // itself; here it only proves the user can be paid at all.
                    _ = try await destination
                    return try await profile
                }

                let userID: UserID
                switch identifier {
                case .userID(let resolvedUserID):
                    userID = resolvedUserID
                case .username:
                    // A handle link learns whose card it is only from the
                    // response, so the id is load-bearing rather than
                    // confirmatory here.
                    guard let responseUserID = resolved.userID else {
                        throw UnidentifiedRecipient()
                    }
                    userID = responseUserID
                }

                guard !Task.isCancelled else { return }
                // The second half of the own-handle check `begin(username:)`
                // starts: a link to your own handle followed before the local
                // profile has loaded its handle only shows itself here.
                guard userID != session.userID else {
                    showOwnTipCard()
                    return
                }

                session.cacheUserProfile(resolved, for: userID)
                let recipient = TipRecipient(
                    userID: userID,
                    displayName: resolved.displayName ?? "",
                    username: resolved.username,
                    origin: .tipcard
                )
                guard !Task.isCancelled else { return }
                present(recipient)
                await loadAvatar(for: recipient, picture: resolved.profilePicture)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to prepare tip recipient", metadata: [
                    "recipient": "\(identifier)",
                    "error": "\(error)",
                ])
                ErrorReporting.captureError(error, reason: "Failed to prepare tip recipient")
                session.dialogItem = Self.failureDialog(for: error, handle: handle)
            }
        }
    }

    /// The dialog a failed resolve earns.
    ///
    /// An id comes off a code the camera just read, so a miss there is a fetch
    /// that didn't land. A handle is the opposite: it is typed, printed on
    /// merch, or pasted out of a bio, and it goes stale the moment its owner
    /// changes it. An unclaimed one is therefore a fact about the link rather
    /// than a fault in the app — informational, and specific about whose handle
    /// went nowhere. Only the network case is ours to apologise for.
    ///
    /// Copy is shared with Android, which splits the same two cases.
    static func failureDialog(for error: Error, handle: Username?) -> DialogItem {
        if let handle, isUnclaimed(error) {
            return .info(
                title: "No Such Account",
                subtitle: "Nobody has claimed @\(handle.value)"
            )
        }

        return .error(
            title: "Couldn't Open Tip Card",
            subtitle: "Please check your connection and try again"
        )
    }

    /// Whether `error` means the handle belongs to nobody. Both halves of the
    /// resolve can say so: `resolve` throws `.notFound`, while `fetchProfile`
    /// returns an id-less `Profile.empty` that becomes `UnidentifiedRecipient`.
    private static func isUnclaimed(_ error: Error) -> Bool {
        switch error {
        case is UnidentifiedRecipient:      true
        case let error as ErrorResolve:     error == .notFound
        case let error as ErrorFetchProfile: error == .notFound
        default:                            false
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
            username: recipient.username.map(\.handle),
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
            if let dialog = giveCashGate(session: session, rate: rate)
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
              case .tipcard(let codeData, let name, let username, _) = session.billState.bill else { return }
        session.billState.bill = .tipcard(codeData: codeData, name: name, username: username, avatar: avatar)
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
    /// disable tokens that can't fund even the smallest tip. No floor means the
    /// server remains the authority — every token stays enabled.
    func meetsMinimum(_ balance: ExchangedBalance) -> Bool {
        guard let floor = submission?.tipFloor(
            in: balance.exchangedFiat.nativeAmount.currency
        ) else {
            return true
        }
        return floor.isMet(by: balance.exchangedFiat)
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
