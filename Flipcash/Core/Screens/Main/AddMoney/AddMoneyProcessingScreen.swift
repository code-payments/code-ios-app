//
//  AddMoneyProcessingScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Blocking settlement screen for the Add Money flow. Reuses `SwapStatusIcon`
/// and the "Notify Me When Complete" push-permission block verbatim from
/// `SwapProcessingScreen`; the only difference is what it waits on — a USDF
/// balance rise, driven through the in-flow USDC sweep for Coinbase/Other
/// Wallet deposits.
struct AddMoneyProcessingScreen: View {
    @State private var viewModel: AddMoneyProcessingViewModel
    @EnvironmentObject private var client: Client
    @Environment(Session.self) private var session
    @Environment(PushController.self) private var pushController
    @Environment(\.dismissParentContainer) private var dismissParentContainer

    private let input: AddMoneyProcessingInput

    init(input: AddMoneyProcessingInput) {
        self.input = input
        _viewModel = State(wrappedValue: AddMoneyProcessingViewModel(input: input))
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 30) {
                Spacer()

                SwapStatusIcon(displayState: viewModel.displayState)
                    .padding(24)

                VStack(spacing: 12) {
                    Text(viewModel.title)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text(viewModel.subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                Spacer()

                if viewModel.isFinished {
                    Button(viewModel.actionTitle) {
                        dismissParentContainer()
                    }
                    .buttonStyle(.filled)
                    .padding(20)
                } else {
                    Button {
                        Task {
                            if pushController.authorizationStatus == .denied {
                                URL.openSettings()
                            } else {
                                _ = try? await PushController.authorizeAndRegister()
                                await pushController.refreshAuthorizationStatus()
                            }
                        }
                    } label: {
                        if pushController.authorizationStatus == .authorized {
                            HStack(spacing: 10) {
                                Image.asset(.checkmark)
                                    .renderingMode(.template)
                                Text("We'll Notify You")
                            }
                        } else {
                            Text("Notify Me When Complete")
                        }
                    }
                    .buttonStyle(.filled)
                    .disabled(pushController.authorizationStatus == .authorized)
                    .padding(20)
                }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .task {
            // A fresh retrying sweep for this deposit — separate from the
            // scene-phase sweep in SessionAuthenticator. `expectedAtLeast` is
            // left nil so a slightly-short Coinbase delivery still sweeps.
            let sweeper = UsdcSweepOperation(
                accountFetcher: client,
                swapper: client,
                ownerKeyPair: session.ownerKeyPair,
                onSweepCompleted: {}
            )

            await viewModel.run(settlement: session) {
                await sweeper.sweepUntilConverted(maxAttempts: 20, backoff: .seconds(3))
            }

            if viewModel.isSuccess {
                session.updatePostTransaction()
            }
        }
    }
}
