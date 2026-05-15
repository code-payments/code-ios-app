//
//  FundingFlowHost.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Pure mapping from a `FundingOperationState` to the prompt destination the
/// host view should push onto its stack. Lifted out of `FundingFlowHost` so
/// the routing logic is unit-testable without SwiftUI.
nonisolated func fundingPrompt(for state: FundingOperationState) -> FundingPromptDestination? {
    switch state {
    case .awaitingUserAction(.education):
        return .phantomEducation
    case .awaitingUserAction(.confirm):
        return .phantomConfirm
    case .idle, .working, .awaitingExternal, .failed:
        return nil
    }
}

/// View modifier that hosts an in-flight `FundingOperation` on a screen with
/// a `NavigationStack`. Observes the operation's state and pushes the
/// matching prompt destination — education / confirm — when the operation
/// transitions to `.awaitingUserAction(...)`. Operation-type knowledge is
/// confined here so concrete screens (`BuyAmountScreen`, wizard) need only
/// a single line of host wiring.
struct FundingFlowHost: ViewModifier {

    let operation: (any FundingOperation)?

    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .onChange(of: operation?.state) { _, newState in
                guard let newState else { return }
                guard let prompt = fundingPrompt(for: newState) else { return }
                push(prompt)
            }
    }

    private func push(_ prompt: FundingPromptDestination) {
        // Only Phantom uses the user-action prompt steps today. Other
        // operation types (Coinbase) drive their UI through `.awaitingExternal`
        // overlays managed on the host screen.
        guard let phantom = operation as? PhantomFundingOperation else { return }
        switch prompt {
        case .phantomEducation:
            router.push(.phantomEducation(phantom))
        case .phantomConfirm:
            router.push(.phantomConfirm(phantom))
        }
    }
}

extension View {
    /// Apply on a screen owning a `NavigationStack` that an in-flight
    /// `FundingOperation` should be able to push prompt screens onto.
    func fundingFlowHost(_ operation: (any FundingOperation)?) -> some View {
        modifier(FundingFlowHost(operation: operation))
    }
}
