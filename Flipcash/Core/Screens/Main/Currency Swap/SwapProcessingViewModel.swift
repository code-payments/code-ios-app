//
//  SwapProcessingViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.swap-processing")

@Observable
class SwapProcessingViewModel {

    // MARK: - State -

    private(set) var currentState: SwapState = .created
    private(set) var displayState: DisplayState = .processing
    private(set) var isPolling: Bool = false
    private(set) var exchangedFiat: ExchangedFiat?

    var title: String {
        switch displayState {
        case .processing:
            return "This Will Take a Minute"
        case .success:
            if let exchangedFiat {
                switch swapType {
                case .convert where targetMint == .usdf:
                    // Converting into the reserve would read "$1.00 of Dollars" —
                    // the amount alone already says it.
                    return exchangedFiat.nativeAmount.formatted()
                case .buyWithReserves, .buyWithCurrency, .convert:
                    // Convert names its destination via `currencyName`, so the
                    // same "X of <currency>" reads correctly there too.
                    return "\(exchangedFiat.nativeAmount.formatted()) of \(currencyName)"
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
            switch swapType {
            case .buyWithReserves, .buyWithCurrency, .convert:
                return "was just added to your Flipcash wallet"
            }
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
            case .buyWithReserves, .buyWithCurrency:
                "Buying \(currencyName)"
            case .convert:
                "Converting"
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
    private let reporter: SwapCompletionReporter
    /// One-second polls' worth of the inline window already spent on the source screen, deducted from the budget here.
    private let attemptsUsed: Int
    /// The token being bought, or a convert's destination. Feeds analytics, and
    /// the success title's check for a conversion landing in the reserve.
    private let targetMint: PublicKey?
    private let currencyName: String
    private let amount: ExchangedFiat

    // MARK: - Init -

    /// Total slow-path poll budget, one poll per second.
    static let maxAttempts = 90

    init(swapId: SwapId, swapType: SwapType, targetMint: PublicKey? = nil, currencyName: String, amount: ExchangedFiat, attemptsUsed: Int = 0) {
        self.attemptsUsed = attemptsUsed
        self.reporter = SwapCompletionReporter(swapId: swapId, swapType: swapType, targetMint: targetMint, amount: amount)
        self.swapId = swapId
        self.swapType = swapType
        self.targetMint = targetMint
        self.currencyName = currencyName
        self.amount = amount
    }

    // MARK: - Actions -

    func cancel() {
        displayState = .failed
    }

    // MARK: - Fetching -

    func startPolling(client: Client, ownerKeyPair: KeyPair) async {
        guard !isPolling, displayState == .processing else { return }
        isPolling = true

        do {
            let metadata = try await client.pollSwapState(
                swapId: swapId,
                owner: ownerKeyPair,
                maxAttempts: max(1, Self.maxAttempts - attemptsUsed)
            ) { [weak self] state in
                Task { @MainActor in
                    self?.currentState = state
                }
            }

            switch metadata.state {
            case .finalized:
                setSwapDetails()
                reporter.trackTransaction(successful: true)
                displayState = .success
            case .failed, .cancelled:
                reporter.reportSwapFailure(state: metadata.state, reason: "Swap completed with failure state")
                reporter.trackTransaction(successful: false)
                displayState = .failed
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                reporter.reportSwapFailure(state: metadata.state, reason: "Swap timed out in intermediate state")
                reporter.trackTransaction(successful: false)
                displayState = .failed
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., by SwiftUI during navigation
            // transitions on iOS 18). Don't treat as failure — the view
            // will restart the task if still visible.
        } catch {
            // No swap state was ever fetched within the poll budget
            logger.error("Swap polling failed", metadata: ["error": "\(error)"])
            reporter.trackTransaction(successful: false)
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

// MARK: - SwapError -

enum SwapError: Error {
    case failed(state: SwapState)
}

// MARK: - SwapType -

nonisolated enum SwapType: CaseIterable {
    case buyWithReserves
    case buyWithCurrency
    /// Selling one currency straight into another (source → USDF, or source →
    /// another launchpad token). Drives the "Converting" copy.
    case convert
}
