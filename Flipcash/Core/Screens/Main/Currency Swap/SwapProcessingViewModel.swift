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
@Observable
class SwapProcessingViewModel {

    // MARK: - State -

    private(set) var currentState: SwapState = .created
    private(set) var displayState: DisplayState = .processing
    private(set) var isPolling: Bool = false
    private(set) var mintMetadata: StoredMintMetadata?
    private(set) var exchangedFiat: ExchangedFiat?

    var title: String {
        switch displayState {
        case .processing:
            return "This Will Take a Minute"
        case .success:
            if let exchangedFiat, let mintMetadata {
                if swapType.isBuy {
                    return "\(exchangedFiat.converted.formatted()) of \(mintMetadata.name)"
                } else {
                    return "\(exchangedFiat.converted.formatted()) of USD Reserves"
                }
            }
            return "Transaction Complete"
        case .failed:
            return "Something Went Wrong"
        }
    }

    var subtitle: String {
        switch displayState {
        case .processing:
            return "This transaction typically takes about a minute. You may leave the app while it completes"
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
            if swapType.isBuy {
                "Purchasing \(mintMetadata?.name ?? "")"
            } else {
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
    private let fee: ExchangedFiat?

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType, mint: PublicKey, amount: ExchangedFiat, fee: ExchangedFiat? = nil) {
        self.swapId = swapId
        self.swapType = swapType
        self.mint = mint
        self.amount = amount
        self.fee = fee
    }

    // MARK: - Actions -

    func cancel() {
        displayState = .failed
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
                trackTransaction(successful: true)
                displayState = .success
            case .failed, .cancelled:
                trackTransaction(successful: false)
                displayState = .failed
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                trackTransaction(successful: false)
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

    private func trackTransaction(successful: Bool) {
        switch swapType {
        case .buyWithReserves:
            Analytics.tokenPurchase(method: .tokenPurchaseWithReserves, exchangedFiat: amount, successful: successful)
        case .buyWithPhantom:
            Analytics.tokenPurchase(method: .tokenPurchaseWithPhantom, exchangedFiat: amount, successful: successful)
        case .sell:
            Analytics.tokenSell(exchangedFiat: amount, fee: fee, successful: successful)
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
    case buyWithReserves
    case buyWithPhantom
    case sell

    var isBuy: Bool {
        switch self {
        case .buyWithReserves, .buyWithPhantom: true
        case .sell: false
        }
    }
}
