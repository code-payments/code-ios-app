//
//  SwipeFlowShowcase.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if DEBUG
import SwiftUI
import FlipcashUI
import FlipcashCore

/// The swipe showcase's root: the control on its own, and, when signed in, the swipe inside the
/// real amount screen. Opened from Beta Features and by `--swipe-sandbox`.
///
/// The amount flow needs the signed-in `Session` and `RatesController` that `EnterAmountView`
/// reads, so without them (the sandbox) only the control shows.
struct SwipeShowcaseHost: View {

    @Environment(Session.self) private var session: Session?
    @Environment(RatesController.self) private var ratesController: RatesController?

    @State private var page: Page = .looks

    private var isFlowAvailable: Bool {
        session != nil && ratesController != nil
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                if isFlowAvailable {
                    Picker("Showcase", selection: $page) {
                        ForEach(Page.allCases) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                switch isFlowAvailable ? page : .looks {
                case .looks:
                    SwipeShowcaseScreen()
                case .amountFlow:
                    SwipeFlowShowcase()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension SwipeShowcaseHost {

    /// The showcase's two pages.
    private enum Page: String, CaseIterable, Identifiable {
        case looks
        case amountFlow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .looks: "Looks"
            case .amountFlow: "Amount flow"
            }
        }
    }
}

// MARK: - Amount flow -

/// The real `EnterAmountView` laid out as the send screen lays it out, with a swipe whose action
/// is a local sleep that succeeds or fails. Nothing is sent: no view model, session call or network.
struct SwipeFlowShowcase: View {

    @Environment(Session.self) private var session

    @State private var enteredAmount = ""
    @State private var outcome: SwipeShowcaseOutcome = .succeeds

    /// Enabled once there's an amount, standing in for the send screen's `canSend`.
    private func isActionEnabled(_ entered: String) -> Bool {
        guard outcome != .disabled else { return false }
        guard let value = AmountValidator().validate(entered) else { return false }
        return value > 0
    }

    var body: some View {
        let available = session.totalBalance

        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 20)
                .padding(.top, 16)

            EnterAmountView(
                mode: .currency,
                enteredAmount: $enteredAmount,
                subtitle: .balanceWithLimit(available),
                actionEnabled: { isActionEnabled($0) },
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $enteredAmount,
                    hint: .available(available)
                ))
            ) {
                SwipeControl(text: "Swipe to Send", action: outcome.action)
            }
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Controls -

    private var controls: some View {
        Picker("Outcome", selection: $outcome) {
            ForEach(SwipeShowcaseOutcome.allCases) { outcome in
                Text(outcome.title).tag(outcome)
            }
        }
        .pickerStyle(.segmented)
    }
}
#endif
