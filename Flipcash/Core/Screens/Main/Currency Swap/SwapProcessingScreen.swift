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
    @Environment(\.dismissParentContainer) private var dismissParentContainer

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType) {
        _viewModel = StateObject(wrappedValue: SwapProcessingViewModel(
            swapId: swapId,
            swapType: swapType
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

                CodeButton(
                    style: .filled,
                    title: "Done"
                ) {
                    dismissParentContainer()
                }
                .disabled(!viewModel.isFinished)
                .padding(20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(true)
        .task {
            await viewModel.startPolling(client: client, ownerKeyPair: session.ownerKeyPair)
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
