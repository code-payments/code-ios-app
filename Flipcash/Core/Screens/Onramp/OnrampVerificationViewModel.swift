//
//  OnrampVerificationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Drives the Coinbase onramp KYC flow: phone verification → email
/// verification → KYC info collection. Generic over the verifier types so
/// callers, tests, and previews can substitute any `PhoneVerifying` /
/// `EmailVerifying` conformer. Wires their callbacks to drive the shared
/// `OnrampVerificationPath`, and owns its own continuation via the
/// `Verifying` base extension.
@Observable
@MainActor
final class OnrampVerificationViewModel<P: PhoneVerifying, E: EmailVerifying>: Verifying {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                phoneVerifier.reset()
                emailVerifier.reset()
            }
        }
    }

    var dialogItem: DialogItem?

    /// Onramp doesn't surface a resend control of its own — defers to whichever
    /// inner verifier is currently active. Kept on the protocol for symmetry.
    var isResending: Bool {
        phoneVerifier.isResending || emailVerifier.isResending
    }

    // MARK: - Composed verifiers (DI) -

    let phoneVerifier: P
    let emailVerifier: E

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session

    // MARK: - Verifying lifecycle hooks -

    @ObservationIgnored var onCodeRequested: (@MainActor () -> Void)?
    @ObservationIgnored var onVerified: (@MainActor () -> Void)?

    /// Internal hook for the `Verifying` default `run`/`cancel`/`finish`
    /// implementations.
    @ObservationIgnored var continuation: CheckedContinuation<Void, Error>?

    // MARK: - Pushed navigation -

    /// Set when the flow runs on the app's navigation stack rather than in a
    /// sheet: step advances push through it instead of appending to the
    /// view-model-owned `verificationPath`. Sheet hosts (`VerifyInfoScreen`)
    /// leave it nil and let `verificationPath` drive their own
    /// `NavigationStack`.
    @ObservationIgnored var pushedHost: PushedVerificationHost?

    /// Advances to `step` — pushing onto the app's navigation stack when the
    /// flow is hosted there, otherwise appending to the sheet-owned
    /// `verificationPath`.
    private func advance(to step: OnrampVerificationPath) {
        if let pushedHost {
            pushedHost.advance(to: step)
        } else {
            verificationPath.append(step)
        }
    }

    /// Called by the pushed host when `step` leaves the screen. SwiftUI reports
    /// that both when a step is popped and when the next one covers it, so the
    /// flow is cancelled only if the root step went away because the host stack
    /// unwound — the user backed out of verification. A no-op once the flow has
    /// finished, since the continuation is already cleared.
    func cancelIfBackedOut(from step: OnrampVerificationPath) {
        guard let pushedHost, step == pushedHost.rootStep, pushedHost.hasUnwound else { return }
        cancel()
    }

    // MARK: - Init -

    /// Primary DI init — accepts any conformers of the verifier protocols.
    /// Tests and previews construct their own conformers and inject them here.
    init(
        session: Session,
        phoneVerifier: P,
        emailVerifier: E
    ) {
        self.session = session
        self.phoneVerifier = phoneVerifier
        self.emailVerifier = emailVerifier

        phoneVerifier.onCodeRequested = { [weak self] in
            guard let self else { return }
            advance(to: .confirmPhoneNumberCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmPhone)
        }
        phoneVerifier.onVerified = { [weak self] in
            self?.navigateToEmailOrFinish()
        }
        emailVerifier.onCodeRequested = { [weak self] in
            guard let self else { return }
            advance(to: .confirmEmailCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmEmail)
        }
        emailVerifier.onVerified = { [weak self] in
            self?.finish()
        }
    }

    // `@_optimize(none)` skips the SIL optimizer for this deinit. Without it,
    // Swift 6.3's `EarlyPerfInliner` crashes when checking layout-constraint
    // compatibility through the generic parameters of this class on `-O`
    // archive builds.
    @_optimize(none)
    isolated deinit {
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    /// Onramp overrides the base `cancel()` to cascade through the inner
    /// verifiers (idempotent for inner continuations in wrapped mode; needed
    /// to reach the inner email verifier's deeplink task).
    func cancel() {
        phoneVerifier.cancel()
        emailVerifier.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    func reset() {
        phoneVerifier.reset()
        emailVerifier.reset()
    }

    // MARK: - Verifying contract -

    var isAlreadyVerified: Bool {
        phoneVerifier.isAlreadyVerified && emailVerifier.isAlreadyVerified
    }

    // MARK: - Navigation -

    /// The first screen the verification sheet shows. When both phone and email
    /// are required it leads with a combined intro (matching Android); a
    /// single-step case goes straight to the needed step (phone if unverified,
    /// email otherwise).
    func initialStep() -> OnrampVerificationPath {
        let needsPhone = !phoneVerifier.isAlreadyVerified
        let needsEmail = !emailVerifier.isAlreadyVerified

        if needsPhone && needsEmail {
            return .intro
        }
        if needsPhone {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            return .enterPhoneNumber
        }
        Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
        return .enterEmail
    }

    /// Advances from the intro to the first real step. The intro only appears
    /// when both phone and email are needed, so phone entry is always next.
    func proceedFromIntro() {
        Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
        advance(to: .enterPhoneNumber)
    }

    private func navigateToEmailOrFinish() {
        if !emailVerifier.isAlreadyVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            advance(to: .enterEmail)
            return
        }

        finish()
    }

    // MARK: - Deeplinks -

    /// Forwards to the inner email verifier and parks the user on the
    /// confirm-email screen so the code check has somewhere to surface.
    /// Navigates only if the verifier took the deeplink — one it drops
    /// (already verified, or another deeplink in flight) must not yank the
    /// user off the step they're on.
    func applyDeeplinkVerification(_ verification: VerificationDescription) {
        guard emailVerifier.applyDeeplinkVerification(verification) else { return }
        showConfirmEmailCode()
    }

    /// Moves the user to the confirm-email step unless they're already there —
    /// pushing onto the host stack when the flow is hosted there, otherwise
    /// replacing the sheet-owned path.
    private func showConfirmEmailCode() {
        if let pushedHost {
            guard pushedHost.currentStep != .confirmEmailCode else { return }
            pushedHost.advance(to: .confirmEmailCode)
        } else if verificationPath.last != .confirmEmailCode {
            verificationPath = [.confirmEmailCode]
        }
    }
}

// MARK: - Pushed hosting -

/// How a verification flow that runs on the app's navigation stack — rather
/// than in its own sheet — reaches that stack, and the record of which of its
/// steps that stack still holds.
///
/// The host stack carries other destinations below the flow and its path is
/// type-erased, so it can only be asked how many steps it holds, never which.
/// This type keeps the step list the count indexes into: the flow pushes
/// through `advance(to:)`, the user pops from the top, so the live steps are
/// always the first `liveStepCount()` of what was pushed.
@MainActor
final class PushedVerificationHost {

    /// The first step pushed onto the host stack. Popping it backs out of
    /// verification entirely; later steps back within the flow.
    let rootStep: OnrampVerificationPath

    private let push: @MainActor (OnrampVerificationPath) -> Void
    private let liveStepCount: @MainActor () -> Int

    private var pushedSteps: [OnrampVerificationPath]

    /// - Parameters:
    ///   - rootStep: the step the caller pushes to open the flow.
    ///   - push: pushes a step onto the host stack.
    ///   - liveStepCount: how many of the flow's steps the host stack holds
    ///     right now — its depth less the depth it had before the flow began.
    init(
        rootStep: OnrampVerificationPath,
        push: @MainActor @escaping (OnrampVerificationPath) -> Void,
        liveStepCount: @MainActor @escaping () -> Int
    ) {
        self.rootStep = rootStep
        self.push = push
        self.liveStepCount = liveStepCount
        self.pushedSteps = [rootStep]
    }

    /// The flow step the user is on, or nil once the stack has unwound past
    /// the flow.
    var currentStep: OnrampVerificationPath? {
        liveSteps.last
    }

    /// `true` once the host stack no longer holds any of the flow's steps.
    var hasUnwound: Bool {
        liveSteps.isEmpty
    }

    /// Pushes `step` onto the host stack, dropping the record of any steps the
    /// user has already popped.
    func advance(to step: OnrampVerificationPath) {
        pushedSteps = Array(liveSteps)
        pushedSteps.append(step)
        push(step)
    }

    private var liveSteps: ArraySlice<OnrampVerificationPath> {
        pushedSteps.prefix(max(0, liveStepCount()))
    }
}

// MARK: - Production wiring -

/// Default concrete combination of phone + email verifiers. Use this
/// typealias at storage sites (e.g. `AddMoneyAmountViewModel`) so they
/// don't have to spell out the generic parameters.
typealias OnrampVerification = OnrampVerificationViewModel<
    PhoneVerificationViewModel,
    EmailVerificationViewModel
>

extension OnrampVerificationViewModel
    where P == PhoneVerificationViewModel, E == EmailVerificationViewModel
{
    /// Convenience init for the production path: constructs concrete
    /// verifiers from the session + flipClient and wires them.
    convenience init(session: Session, flipClient: FlipClient) {
        self.init(
            session: session,
            phoneVerifier: PhoneVerificationViewModel(
                owner: session.ownerKeyPair,
                flipClient: flipClient,
                isAlreadyVerified: { [weak session] in session?.profile?.isPhoneVerified ?? false },
                onShouldRefreshProfile: { [weak session] in try? await session?.updateProfile() },
            ),
            emailVerifier: EmailVerificationViewModel(session: session, flipClient: flipClient)
        )
    }
}
