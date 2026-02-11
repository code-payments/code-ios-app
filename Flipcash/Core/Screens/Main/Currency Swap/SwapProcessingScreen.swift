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
    @StateObject private var viewModel: SwapProcessingViewModel
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var pushController: PushController
    @Environment(\.dismissParentContainer) private var dismissParentContainer

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType, mint: PublicKey, amount: ExchangedFiat) {
        _viewModel = StateObject(wrappedValue: SwapProcessingViewModel(
            swapId: swapId,
            swapType: swapType,
            mint: mint,
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
                    CodeButton(
                        style: .filled,
                        title: viewModel.actionTitle
                    ) {
                        dismissParentContainer()
                    }
                    .padding(20)
                } else {
                    CodeButton(
                        state: pushController.authorizationStatus == .authorized ? .successText("We'll Notify You") : .normal,
                        style: .filled,
                        title: "Notify Me When Complete"
                    ) {
                        Task {
                            if pushController.authorizationStatus == .denied {
                                URL.openSettings()
                            } else {
                                try? await PushController.authorizeAndRegister()
                                await pushController.refreshAuthorizationStatus()
                            }
                        }
                    }
                    .disabled(pushController.authorizationStatus == .authorized)
                    .padding(20)
                }
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .task {
            await viewModel.fetchMintMetadata(session: session)
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
                CircularLoadingView(lineWidth: 5)

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
