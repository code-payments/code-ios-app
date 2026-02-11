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
    @Published private(set) var mintMetadata: StoredMintMetadata?
    @Published private(set) var exchangedFiat: ExchangedFiat?

    var title: String {
        switch displayState {
        case .processing:
            return "Processing Your Transaction"
        case .success:
            if let exchangedFiat, let mintMetadata {
                return "\(exchangedFiat.converted.formatted()) of \(mintMetadata.name)"
            }
            return "Transaction Complete"
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
    
    var navigationTitle: String {
        switch displayState {
        case .processing:
            switch swapType {
            case .buy:
                "Purchasing \(mintMetadata?.name ?? "")"
            case .sell:
                "Selling \(mintMetadata?.name ?? "")"
            }
        case .success:
            "Success"
        case .failed:
            "Transaction Failed"
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
    private let mint: PublicKey
    private let amount: ExchangedFiat

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType, mint: PublicKey, amount: ExchangedFiat) {
        self.swapId = swapId
        self.swapType = swapType
        self.mint = mint
        self.amount = amount
    }

    // MARK: - Fetching -

    func fetchMintMetadata(session: Session) async {
        mintMetadata = try? await session.fetchMintMetadata(mint: mint)
    }

    func startPolling(client: Client, ownerKeyPair: KeyPair) async {
        guard !isPolling else { return }
        isPolling = true

        do {
            let metadata = try await client.pollSwapState(
                swapId: swapId,
                owner: ownerKeyPair,
                maxAttempts: 90
            ) { [weak self] state in
                Task { @MainActor in
                    self?.currentState = state
                }
            }

            switch metadata.state {
            case .finalized:
                setSwapDetails()
                displayState = .success
            case .failed, .cancelled:
                displayState = .failed
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                displayState = .failed
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., by SwiftUI during navigation
            // transitions on iOS 18). Don't treat as failure — the view
            // will restart the task if still visible.
        } catch {
            // Poll limit reached or other error
            displayState = .failed
        }

        isPolling = false
    }
    
    private func setSwapDetails() {
        exchangedFiat = amount
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
