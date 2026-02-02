//
//  SwapProcessingViewModel.swift
//  Flipcash
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

@MainActor
class SwapProcessingViewModel: ObservableObject {

    // MARK: - Published State -

    @Published private(set) var currentState: SwapState = .created
    @Published private(set) var displayState: DisplayState = .processing
    @Published private(set) var isPolling: Bool = false

    var title: String {
        switch displayState {
        case .processing:
            return "Processing Your Transaction"
        case .success:
            return "{{amount}} of {{token}}"
        case .failed:
            return "Something Went Wrong"
        }
    }

    var subtitle: String {
        switch displayState {
        case .processing:
            return "This usually takes just under a minute"
        case .success:
            return "was just added to your Flipcash wallet"
        case .failed:
            return "Please try again later"
        }
    }
    
    var actionTitle: String {
        switch displayState {
        case .processing:
            return "Notify Me When Complete"
        case .success:
            return "OK"
        case .failed:
            return "OK"
        }
    }

    var isSuccess: Bool {
        displayState == .success
    }
    
    var isFinished: Bool {
        displayState != .processing
    }

    // MARK: - Private -

    private let swapId: SwapId
    private let swapType: SwapType

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType) {
        self.swapId = swapId
        self.swapType = swapType
    }

    // MARK: - Polling -

    func startPolling(client: Client, ownerKeyPair: KeyPair) async {
        guard !isPolling else { return }
        isPolling = true

        do {
            let metadata = try await client.pollSwapState(
                swapId: swapId,
                owner: ownerKeyPair,
                maxAttempts: 60
            ) { [weak self] state in
                Task { @MainActor in
                    self?.currentState = state
                }
            }

            handleTerminalState(metadata.state)
        } catch {
            // Poll limit reached or other error
            displayState = .failed
        }

        isPolling = false
    }

    // MARK: - Private Helpers -

    private func handleTerminalState(_ state: SwapState) {
        switch state {
        case .finalized:
            displayState = .success
        case .failed, .cancelled:
            displayState = .failed
        case .unknown, .created, .funding, .funded, .submitting, .cancelling:
            // Should not happen for terminal states
            displayState = .failed
        }
    }
}

// MARK: - DisplayState -

extension SwapProcessingViewModel {
    enum DisplayState {
        case processing
        case success
        case failed
    }
}

// MARK: - SwapType -

enum SwapType {
    case buy
    case sell
}
