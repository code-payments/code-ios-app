//
//  VerificationRouter.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.verification-router")

/// Session-scoped coordinator for verification flows. Splits two
/// concerns that used to live on `OnrampCoordinator`:
///
/// 1. **Inline flows** — `BuyAmountViewModel` / `CurrencyCreationWizardScreen`
///    call `beginInlineFlow()` to get a fresh `VerificationViewModel` and
///    mount the sheet themselves. They `endInlineFlow(_:)` when the awaited
///    `vm.run()` returns or throws.
/// 2. **Out-of-flow deeplinks** — when an email verification link fires while
///    no inline flow is active, the router constructs its own viewmodel,
///    publishes it on `fallbackViewModel`, and `OnrampHostModifier` mounts a
///    sheet at app root.
///
/// If an inline flow is active when a deeplink arrives, the router forwards
/// the deeplink to the inline viewmodel instead of opening the fallback.
@Observable
@MainActor
final class VerificationRouter {

    /// Active inline viewmodel, if any. Set by `beginInlineFlow()`,
    /// cleared by `endInlineFlow(_:)`.
    private(set) var currentInlineViewModel: VerificationViewModel?

    /// Non-nil while the router-owned fallback sheet is presented (e.g. a
    /// deeplink arrived with no inline flow). `OnrampHostModifier` binds
    /// `.sheet(item:)` to this.
    var fallbackViewModel: VerificationViewModel?

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let deeplinkInbox: OnrampDeeplinkInbox

    init(session: Session, flipClient: FlipClient, deeplinkInbox: OnrampDeeplinkInbox) {
        self.session = session
        self.flipClient = flipClient
        self.deeplinkInbox = deeplinkInbox
    }

    // MARK: - Caller-facing gate -

    /// Verification gate for funding operations. If the profile is already
    /// fully verified, runs `perform` immediately. Otherwise constructs a
    /// `VerificationViewModel`, hands it to `bind` so the caller can mount
    /// the sheet, awaits the user completing verification, and then runs
    /// `perform`. Cleans up the inline-flow slot and clears the caller's
    /// binding on completion or cancellation.
    func runGated(
        for session: Session,
        bind: @MainActor @escaping (VerificationViewModel?) -> Void,
        perform: @MainActor @escaping () -> Void
    ) {
        if let profile = session.profile,
           profile.isPhoneVerified,
           profile.isEmailVerified {
            perform()
            return
        }
        guard let vm = beginInlineFlow() else { return }
        bind(vm)
        Task { [weak self, vm] in
            defer {
                self?.endInlineFlow(vm)
                bind(nil)
            }
            do {
                try await vm.run()
            } catch {
                return
            }
            perform()
        }
    }

    // MARK: - Inline flows -

    /// Returns a fresh viewmodel for the caller to drive. If a previous
    /// inline flow is still active, returns nil (caller should treat this as
    /// a no-op — the user already has a sheet up). Drains any buffered
    /// deeplink into the new viewmodel so a link that landed before the
    /// caller started doesn't get lost.
    func beginInlineFlow() -> VerificationViewModel? {
        guard currentInlineViewModel == nil else {
            logger.warning("beginInlineFlow called while another flow is active")
            return nil
        }
        let vm = VerificationViewModel(session: session, flipClient: flipClient)
        currentInlineViewModel = vm
        if let pending = deeplinkInbox.pendingEmailVerification {
            vm.applyDeeplinkVerification(pending)
            deeplinkInbox.pendingEmailVerification = nil
        }
        return vm
    }

    /// Releases the inline-flow slot so future deeplinks can either open the
    /// fallback or be forwarded to a new inline flow. Idempotent.
    func endInlineFlow(_ vm: VerificationViewModel) {
        guard currentInlineViewModel === vm else { return }
        currentInlineViewModel = nil
    }

    // MARK: - Deeplinks -

    /// Called by `OnrampHostModifier` on every change to
    /// `OnrampDeeplinkInbox.pendingEmailVerification`. Hands the deeplink
    /// off to the active inline viewmodel if there is one; otherwise opens
    /// the fallback sheet with a freshly constructed viewmodel.
    func receiveDeeplinkIfPending() {
        guard let pending = deeplinkInbox.pendingEmailVerification else { return }
        deeplinkInbox.pendingEmailVerification = nil

        if let active = currentInlineViewModel {
            active.applyDeeplinkVerification(pending)
            return
        }

        let vm = VerificationViewModel(session: session, flipClient: flipClient)
        fallbackViewModel = vm
        vm.applyDeeplinkVerification(pending)

        Task { [weak self, weak vm] in
            // Drain the run() suspension whether it completes or cancels —
            // either way we dismiss the fallback sheet by clearing the slot.
            try? await vm?.run()
            guard let self, let vm, self.fallbackViewModel === vm else { return }
            self.fallbackViewModel = nil
        }
    }
}
