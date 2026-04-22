//
//  CurrencyLaunchProcessingScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencyLaunchProcessingScreen: View {
    @State private var viewModel: CurrencyLaunchProcessingViewModel
    @EnvironmentObject private var client: Client
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(PushController.self) private var pushController
    @Environment(\.dismissParentContainer) private var dismissParentContainer

    // MARK: - Init -

    init(swapId: SwapId, launchedMint: PublicKey, currencyName: String, launchAmount: ExchangedFiat, fundingMethod: CurrencyLaunchProcessingViewModel.FundingMethod) {
        _viewModel = State(wrappedValue: CurrencyLaunchProcessingViewModel(
            swapId: swapId,
            launchedMint: launchedMint,
            currencyName: currencyName,
            launchAmount: launchAmount,
            fundingMethod: fundingMethod
        ))
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 30) {
                Spacer()

                LaunchStatusIcon(displayState: viewModel.displayState)
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

                PrimaryActionButton(
                    viewModel: viewModel,
                    pushController: pushController,
                    onReceive: { Task { await handleReceiveLaunchedCurrency() } },
                    onDismiss: { dismissParentContainer() }
                )
                .padding(20)
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .task {
            await viewModel.startPolling(
                client: client,
                session: session,
                ratesController: ratesController
            )

            if viewModel.isSuccess {
                session.updatePostTransaction()
            }
        }
    }

    private func handleReceiveLaunchedCurrency() async {
        let description = await viewModel.prepareBillHandoff(
            session: session,
            ratesController: ratesController
        )
        if let description {
            session.showCashBill(description)
        }
        dismissParentContainer()
    }
}

// MARK: - PrimaryActionButton -

private struct PrimaryActionButton: View {
    @Bindable var viewModel: CurrencyLaunchProcessingViewModel
    let pushController: PushController
    let onReceive: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch viewModel.displayState {
        case .processing:
            NotifyPermissionButton(
                actionTitle: viewModel.actionTitle,
                pushController: pushController
            )

        case .success:
            Button(viewModel.actionTitle, action: onReceive)
                .buttonStyle(.filled)
                .disabled(viewModel.isReceivingBill)

        case .failed:
            Button(viewModel.actionTitle, action: onDismiss)
                .buttonStyle(.filled)
        }
    }
}

// MARK: - NotifyPermissionButton -

private struct NotifyPermissionButton: View {
    let actionTitle: String
    let pushController: PushController

    var body: some View {
        Button(action: handleTap) {
            if pushController.authorizationStatus == .authorized {
                HStack(spacing: 10) {
                    Image.asset(.checkmark)
                        .renderingMode(.template)
                    Text("We'll Notify You")
                }
            } else {
                Text(actionTitle)
            }
        }
        .buttonStyle(.filled)
        .disabled(pushController.authorizationStatus == .authorized)
    }

    private func handleTap() {
        Task {
            if pushController.authorizationStatus == .denied {
                URL.openSettings()
            } else {
                _ = try? await PushController.authorizeAndRegister()
                await pushController.refreshAuthorizationStatus()
            }
        }
    }
}

// MARK: - LaunchStatusIcon -

private struct LaunchStatusIcon: View {
    let displayState: CurrencyLaunchProcessingViewModel.DisplayState

    private let iconSize: CGFloat = 100

    var body: some View {
        Group {
            switch displayState {
            case .processing:
                // Covers swap polling (120 × 1 s) + awaitBalance (60 × 2 s) worst case.
                CircularLoadingView(duration: 240)

            case .success:
                Image("IconCircleCheck")
                    .resizable()

            case .failed:
                Image("IconExclamationCircle")
                    .resizable()
            }
        }
        .frame(width: iconSize, height: iconSize)
    }
}
