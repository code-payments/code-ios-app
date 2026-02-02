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

    // MARK: - Init -

    init(swapId: SwapId, swapType: SwapType, mint: PublicKey) {
        self.swapId = swapId
        self.swapType = swapType
        self.mint = mint
    }

    // MARK: - Fetching -

    func fetchMintMetadata(session: Session) async {
        mintMetadata = try? await session.fetchMintMetadata(mint: mint)
    }

    func startPolling(client: Client, ownerKeyPair: KeyPair, session: Session, ratesController: RatesController) async {
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
            
            switch metadata.state {
            case .finalized:
                fetchSwapDetails(from: metadata, ratesController: ratesController)
                displayState = .success
            case .failed, .cancelled:
                displayState = .failed
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                displayState = .failed
            }
        } catch {
            // Poll limit reached or other error
            displayState = .failed
        }

        isPolling = false
    }
    
    private func fetchSwapDetails(from metadata: SwapMetadata, ratesController: RatesController) {
        guard let mintMetadata else {
            print("[SwapProcessing] mintMetadata is nil")
            return
        }

        let rate = ratesController.rateForEntryCurrency()

        print("[SwapProcessing] Input:")
        print("  - metadata.amount.quarks: \(metadata.amount.quarks)")
        print("  - metadata.toMint: \(metadata.toMint.base58)")
        print("  - rate: \(rate)")
        print("  - mintMetadata.supplyFromBonding: \(String(describing: mintMetadata.supplyFromBonding))")

        exchangedFiat = ExchangedFiat.computeFromQuarks(
            quarks: metadata.amount.quarks,
            mint: metadata.toMint,
            rate: rate,
            supplyQuarks: mintMetadata.supplyFromBonding
        )

        if let exchangedFiat {
            print("[SwapProcessing] Output:")
            print("  - exchangedFiat.underlying.quarks: \(exchangedFiat.underlying.quarks)")
            print("  - exchangedFiat.converted.quarks: \(exchangedFiat.converted.quarks)")
            print("  - exchangedFiat.converted.formatted(): \(exchangedFiat.converted.formatted())")
        } else {
            print("[SwapProcessing] exchangedFiat is nil after computation")
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
