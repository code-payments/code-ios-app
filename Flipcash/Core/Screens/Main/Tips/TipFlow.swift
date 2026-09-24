//
//  TipFlow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.tip-flow")

/// Session-scoped orchestrator for opening someone's tipcard. Entered from a
/// scanned tipcode or a tipcard link, it gates the entry (profile), resolves
/// the recipient, shows the card, and hands over to their chat — where the
/// amount is chosen and sent (node 10074:18893).
@Observable
final class TipFlow {

    /// A recipient held while the user creates a profile; resumed by
    /// ``resumeAfterProfileCreation()`` once `isTippable` flips true. Holds
    /// whichever identifier the entry carried — a scanned code's user id or a
    /// vanity link's handle.
    @ObservationIgnored private(set) var pendingRecipient: ProfileIdentifier?

    @ObservationIgnored private var prepTask: Task<Void, Never>?

    /// The hold between the card landing and the chat opening. Held so a
    /// dismissed card cancels the hand-off, and so a second entry can't start
    /// while one is mid-flight.
    @ObservationIgnored private var routeTask: Task<Void, Never>?

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

    // MARK: - Entry -

    /// Handles a scanned or deeplinked tipcode. Gates in order: own-id codes
    /// (routed to the user's own tip card), then a tippable profile (held +
    /// profile creation presented).
    ///
    /// No balance gate: this flow no longer moves money, it opens a chat. The
    /// giveable-balance check belongs to the send the chat makes, and
    /// `ConversationScreen.sendCash()` already applies it there — gating the
    /// card as well would stop an empty-balance user from reaching a
    /// conversation they can read and reply in.
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
        guard pendingRecipient == nil, prepTask == nil, routeTask == nil else { return }
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

    /// Tears down the card and any in-flight preparation or hand-off.
    /// Idempotent — safe from the drag-dismissed card and from a failed
    /// resolve alike.
    func cancel() {
        prepTask?.cancel()
        prepTask = nil
        routeTask?.cancel()
        routeTask = nil
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

                // The chat is created by the first tip, so until then the
                // conversation's only source for the counterpart's name,
                // picture, and handle is the profile this resolve fetched.
                session.cacheUserProfile(resolved, for: userID)
                guard !Task.isCancelled else { return }
                present(userID: userID, profile: resolved)
                await loadAvatar(userID: userID, picture: resolved.profilePicture)
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

    /// Shows the resolved card, holds it long enough to read whose it is, then
    /// pops it away as the chat with them pushes in underneath.
    ///
    /// The card is the confirmation that the right code was scanned, not a
    /// place to compose from: the amount is chosen in the chat, behind the
    /// "Start Chatting" CTA, which is where the username lookup already lands
    /// (node 10074:18893).
    private func present(userID: UserID, profile: Profile) {
        // The card is resolved and about to show, whether reached from a scan or
        // a deep link — the second step of the Scanned → Presented → Sent Tip funnel.
        Analytics.tipCardPresented()
        // Again, because the resolve above retries: a cold-foreground `.unavailable`
        // outlasts the window opened at `begin`, so the restore can win after it has
        // closed. The card is a focused modal and must never share the screen with a
        // keyboard, so it takes one down on the way up regardless.
        keyboard.suppress()

        // A tip deep link can beat the app's foreground stream refresh, so kick the
        // rate stream to reconnect now, while the card animates in. The chat's CTA
        // names the fee in the display currency and its amount screen priced in it,
        // so both want a rate the moment they appear.
        ratesController.ensureStreamConnected()

        session.billState = BillState(bill: .tipcard(
            codeData: TipCode.Payload(userID: userID).codeData(),
            name: profile.displayName ?? "",
            username: profile.username.map(\.handle),
            avatar: nil
        ))
        session.presentationState = .visible(.pop)

        // The card's pop is given 750ms to settle and be read, then it leaves
        // and the chat arrives together: the dismissal and the route happen in
        // the same tick, so the card's 100ms exit plays over the chat pushing
        // in rather than handing back to the camera in between. Cancelled by
        // `cancel()`, so a card the user drags away during the hold never drops
        // them into a chat they backed out of.
        routeTask = Task { [weak self] in
            defer { self?.routeTask = nil }
            try? await Task.delay(milliseconds: 750)
            guard let self, !Task.isCancelled else { return }

            if case .tipcard = session.billState.bill {
                session.dismissCashBill(style: .pop)
            }

            // `navigate` rather than `push`: the card is an app-root overlay
            // raised over whichever tab the scan or link arrived on, and a tip
            // DM belongs on the Tips stack. This brings that tab forward with
            // the chat as its only entry, so Back lands on the chat list.
            router.navigate(to: .tipConversationForUser(userID))
        }
    }

    /// Fetches the recipient's avatar through the shared profile-avatar store —
    /// warming the same cache the conversation surfaces read — and re-renders
    /// the card with it. The card is already up, so a failure just leaves the
    /// placeholder.
    private func loadAvatar(userID: UserID, picture: ProfilePicture?) async {
        let store = sessionContainer.profileAvatars
        await store.load(userID: userID, picture: picture)
        guard let data = store.data(for: userID),
              let avatar = UIImage(data: data),
              case .tipcard(let codeData, let name, let username, _) = session.billState.bill else { return }
        session.billState.bill = .tipcard(codeData: codeData, name: name, username: username, avatar: avatar)
    }
}
