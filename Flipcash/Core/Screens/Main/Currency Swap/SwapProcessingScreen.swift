//
//  SwapProcessingScreen.swift
//  Flipcash
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SwapProcessingScreen: View {
    @State private var viewModel: SwapProcessingViewModel
    @EnvironmentObject private var client: Client
    @Environment(Session.self) private var session
    @Environment(PushController.self) private var pushController
    @Environment(\.dismissParentContainer) private var dismissParentContainer
    @Environment(WalletConnection.self) private var walletConnection

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType, currencyName: String, amount: ExchangedFiat) {
        _viewModel = State(wrappedValue: SwapProcessingViewModel(
            swapId: swapId,
            swapType: swapType,
            currencyName: currencyName,
            amount: amount
        ))
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 30) {
                Spacer()

                // Status Icon
                SwapStatusIcon(displayState: viewModel.displayState)
                    .padding(24)

                // Status Text
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
                                try? await PushController.authorizeAndRegister()
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .onChange(of: walletConnection.isProcessingCancelled, initial: true) { _, cancelled in
            if cancelled {
                viewModel.cancel()
            }
        }
        .task {
            await viewModel.startPolling(
                client: client,
                ownerKeyPair: session.ownerKeyPair
            )

            if viewModel.isSuccess {
                session.updatePostTransaction()
            }
        }
    }
}

// MARK: - SwapStatusIcon -

struct SwapStatusIcon: View {
    let displayState: SwapProcessingViewModel.DisplayState

    private let iconSize: CGFloat = 100

    var body: some View {
        Group {
            switch displayState {
            case .processing:
                CircularLoadingView(duration: 60)

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
