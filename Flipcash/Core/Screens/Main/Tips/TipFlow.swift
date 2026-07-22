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
    var selection: TipSelection = .low

    /// The direct-send engine for the presented recipient. Owns the target,
    /// the selected balance, and the full submission path (minimum, funds,
    /// pin, limits). Non-nil exactly while a tip is being composed.
    private(set) var submission: SendAmountViewModel?

    /// A recipient held while the user creates a profile; resumed by
    /// ``resumeAfterProfileCreation()`` once `isTippable` flips true.
    @ObservationIgnored private(set) var pendingUserID: UserID?

    @ObservationIgnored private var prepTask: Task<Void, Never>?

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
    func amount(for selection: TipSelection) -> Decimal? {
        switch selection {
        case .low:    presets?.low
        case .medium: presets?.medium
        case .high:   presets?.high
        case .custom: customAmount
        }
    }

    /// The fiat amount the current selection stands for.
    var selectedAmount: Decimal? {
        amount(for: selection)
    }

    // MARK: - Entry -

    /// Handles a scanned or deeplinked tipcode. Gates in order: the feature
    /// flag, own-id scans (ignored), a tippable profile (held + profile
    /// creation presented), then a giveable balance (Add Money / Discover
    /// dialog). Passing all of them fetches the recipient and presents the
    /// card + sheet.
    func begin(userID: UserID) {
        guard session.canUseTips else { return }
        guard userID != session.userID else { return }
        guard submission == nil, pendingUserID == nil, prepTask == nil else { return }
        // A dialog is already asking the user something (commonly this flow's
        // own balance gate) — don't churn it on every decoded camera frame.
        guard session.dialogItem == nil else { return }

        guard session.profile?.isTippable == true else {
            pendingUserID = userID
            logger.info("Tip held for profile creation", metadata: ["recipient": "\(userID)"])
            router.present(.tips)
            return
        }

        let rate = ratesController.rateForBalanceCurrency()
        if let dialog = giveCashGate(session: session, rate: rate)
            .blockingDialog(router: router, addMoneySource: .scanner, context: .sendTips) {
            session.dialogItem = dialog
            return
        }

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
                async let profile = flipClient.fetchProfile(userID: userID, owner: session.ownerKeyPair)
                async let destination = flipClient.resolveUserID(userID, owner: session.ownerKeyPair)
                // The destination is re-resolved (and cached) by the send
                // itself; here it only proves the user can be paid at all.
                _ = try await destination
                let recipient = TipRecipient(
                    userID: userID,
                    displayName: try await profile.displayName ?? ""
                )
                guard !Task.isCancelled else { return }
                present(recipient)
                await loadAvatar(for: recipient, picture: try await profile.profilePicture)
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
        selection = .low
        customAmount = nil
        submission = SendAmountViewModel(
            sessionContainer: sessionContainer,
            target: .tip(recipient)
        )

        session.billState = BillState(bill: .tipcard(
            codeData: TipCode.Payload(userID: recipient.userID).codeData(),
            name: recipient.displayName,
            avatar: nil
        ))
        session.presentationState = .visible(.pop)

        // The sheet follows once the card's pop has settled, mirroring the
        // received-cash valuation timing. `submission` is nilled by `cancel()`,
        // so a card dismissed during the delay never presents a stale sheet.
        Task {
            try? await Task.delay(milliseconds: 750)
            guard submission != nil else { return }
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
            router.navigate(to: .tipConversation(chatID))
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
