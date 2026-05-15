//
//  PhantomFlowScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Single host for the Phantom funding flow. Renders one of:
/// - The education panel during `.awaitingUserAction(.education)` and
///   `.awaitingExternal(.phantomConnect)`.
/// - The confirm panel during `.awaitingUserAction(.confirm)`,
///   `.awaitingExternal(.phantomSign)`, and the post-sign `.working` submit
///   window (gated by `hasShownConfirm`).
/// - `EmptyView` during pre-prompt windows (launch preflight `.working`,
///   initial `.idle`) and terminal states — the screen gets replaced or the
///   sheet dismisses before the gap is visible.
///
/// The CTA always calls `fundingOperation.confirm()`, which resumes the
/// suspended continuation inside `PhantomFundingOperation.run()`. Wallet-side
/// cancellations loop the operation back to the relevant `awaitingUserAction`
/// state and surface a "Transaction Cancelled" dialog via `session.dialogItem`
/// — the screen stays mounted so the user can tap the CTA again to retry.
struct PhantomFlowScreen: View {

    let fundingOperation: PhantomFundingOperation

    @Environment(Session.self) private var session
    /// Sticky once-true flag — set when the operation first hits the Confirm
    /// prompt (or `.awaitingExternal(.phantomSign)` as a defensive guard).
    /// Lets the screen keep showing the Confirm panel through the subsequent
    /// `.awaitingExternal(.phantomSign)` and `.working` (submit) windows.
    /// Before that, `.working` means launch preflight — nothing to show.
    @State private var hasShownConfirm: Bool = false

    var body: some View {
        Background(color: .backgroundMain) {
            PhantomFlowContent(
                fundingOperation: fundingOperation,
                hasShownConfirm: hasShownConfirm
            )
            .padding(20)
        }
        .navigationTitle(hasShownConfirm ? "Confirmation" : "Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Idempotent — cancelling a terminal operation is a no-op,
            // so we don't need to gate on state.
            fundingOperation.cancel()
        }
        // Surface wallet-side cancels through the session-level dialog so
        // the alert renders above the flow sheet (per CLAUDE.md's
        // cross-sheet dialog pattern). `confirm()` clears
        // `lastErrorMessage` so each subsequent cancel re-fires this
        // transition.
        .onChange(of: fundingOperation.lastErrorMessage) { _, newMessage in
            guard newMessage != nil else { return }
            session.dialogItem = .walletCancelled
        }
        .onChange(of: fundingOperation.state) { _, newState in
            // Set on either gate that proves we've passed the connect step
            // — `.awaitingUserAction(.confirm)` is the normal entry, but
            // accepting `.phantomSign` too keeps this robust to any
            // future reorder of the operation's state machine.
            switch newState {
            case .awaitingUserAction(.confirm), .awaitingExternal(.phantomSign):
                hasShownConfirm = true
            default:
                break
            }
        }
    }
}

// MARK: - Content router

/// Switches between the panels for each `FundingOperationState`. Kept as a
/// dedicated `View` (not a computed property on `PhantomFlowScreen`) so the
/// scaffold doesn't re-execute its switch when nav-title state changes.
private struct PhantomFlowContent: View {

    let fundingOperation: PhantomFundingOperation
    let hasShownConfirm: Bool

    var body: some View {
        switch fundingOperation.state {
        case .awaitingUserAction(.education):
            PhantomEducationPanel(buttonState: .idle, onTap: fundingOperation.confirm)

        case .awaitingExternal(.phantomConnect):
            PhantomEducationPanel(buttonState: .busy("Connecting…"), onTap: fundingOperation.confirm)

        case .awaitingUserAction(.confirm):
            PhantomConfirmPanel(buttonState: .idle, onTap: fundingOperation.confirm)

        case .awaitingExternal(.phantomSign):
            PhantomConfirmPanel(buttonState: .busy("Waiting for Phantom…"), onTap: fundingOperation.confirm)

        case .working:
            // Post-sign submit: keep the Confirm panel busy so the visual
            // doesn't jump on the wallet → chain hand-off. Launch preflight
            // also writes `.working`, but it happens before the Confirm
            // prompt has ever been shown — nothing to render.
            if hasShownConfirm {
                PhantomConfirmPanel(buttonState: .busy("Waiting for Phantom…"), onTap: fundingOperation.confirm)
            } else {
                EmptyView()
            }

        case .idle, .failed, .awaitingExternal(.applePay):
            // Terminal or defensive — operation is done (screen about to be
            // replaced/popped) or the prompt isn't ours.
            EmptyView()
        }
    }
}

// MARK: - Panels

private struct PhantomEducationPanel: View {

    let buttonState: PhantomFlowButtonState
    let onTap: () -> Void

    var body: some View {
        PhantomFlowPanel(
            title: "Buy With Phantom",
            subtitle: "Purchase using Solana USDC in Phantom. Simply connect your wallet and confirm the transaction",
            buttonState: buttonState,
            accessibilityHeroLabel: "Buy with Phantom using Solana USDC",
            onTap: onTap
        ) {
            PhantomEducationHero()
        } buttonLabel: {
            Text("Connect Your Phantom Wallet")
        }
    }
}

private struct PhantomConfirmPanel: View {

    let buttonState: PhantomFlowButtonState
    let onTap: () -> Void

    var body: some View {
        PhantomFlowPanel(
            title: "Connected",
            subtitle: "Confirm the transaction in Phantom to continue",
            buttonState: buttonState,
            accessibilityHeroLabel: "Phantom connected",
            onTap: onTap
        ) {
            BadgedIcon(
                icon: Image.asset(.buyPhantom),
                badge: Image.asset(.buyCheckmark)
            )
        } buttonLabel: {
            HStack(spacing: 6) {
                Text("Confirm in your")
                Image.asset(.phantom)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text("Phantom")
            }
        }
    }
}

// MARK: - Shared scaffold

private enum PhantomFlowButtonState: Equatable {
    case idle
    case busy(String)

    var isBusy: Bool {
        if case .busy = self { return true }
        return false
    }
}

/// Shared layout for the two Phantom panels: hero on top, title+subtitle
/// underneath, CTA at bottom. Generic over the hero and CTA-label views so
/// each panel supplies only the bits that differ.
private struct PhantomFlowPanel<Hero: View, ButtonLabel: View>: View {

    let title: String
    let subtitle: String
    let buttonState: PhantomFlowButtonState
    let accessibilityHeroLabel: String
    let onTap: () -> Void
    @ViewBuilder let hero: Hero
    @ViewBuilder let buttonLabel: ButtonLabel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            hero
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityHeroLabel)

            VStack(spacing: 8) {
                Text(title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)

                Text(subtitle)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            Spacer()

            Button(action: onTap) {
                PhantomFlowButtonLabel(state: buttonState) {
                    buttonLabel
                }
            }
            .buttonStyle(.filled)
            .disabled(buttonState.isBusy)
        }
    }
}

private struct PhantomFlowButtonLabel<Label: View>: View {

    let state: PhantomFlowButtonState
    @ViewBuilder let label: Label

    var body: some View {
        switch state {
        case .idle:
            label
        case .busy(let text):
            HStack(spacing: 8) {
                ProgressView().progressViewStyle(.circular)
                Text(text)
            }
        }
    }
}

// MARK: - Hero variants

private struct PhantomEducationHero: View {
    var body: some View {
        HStack(spacing: 16) {
            BadgedIcon(icon: Image.asset(.buyPhantom))

            Image(systemName: "plus")
                .foregroundStyle(Color.textMain)
                .font(.system(size: 20, weight: .medium))

            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana)
            )
        }
    }
}

