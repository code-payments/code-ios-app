//
//  CurrencyLaunchProcessingViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.currency-launch-processing")

@MainActor
@Observable
class CurrencyLaunchProcessingViewModel {

    // MARK: - State -

    /// Writable at the target level so test support extensions can drive
    /// deterministic state transitions. Production code only mutates this from
    /// `startPolling` and `cancel`.
    var displayState: DisplayState = .processing
    private(set) var currentState: SwapState = .created
    private(set) var isReceivingBill: Bool = false
    private(set) var isPolling: Bool = false

    // MARK: - Inputs -

    let currencyName: String
    let launchAmount: ExchangedFiat
    let launchedMint: PublicKey
    let fundingMethod: FundingMethod

    // MARK: - Private -

    private let swapId: SwapId

    // MARK: - Init -

    init(swapId: SwapId, launchedMint: PublicKey, currencyName: String, launchAmount: ExchangedFiat, fundingMethod: FundingMethod) {
        self.swapId = swapId
        self.launchedMint = launchedMint
        self.currencyName = currencyName
        self.launchAmount = launchAmount
        self.fundingMethod = fundingMethod
    }

    // MARK: - Copy -

    var navigationTitle: String {
        switch displayState {
        case .processing: "Creating \(currencyName)"
        case .success:    "Success"
        case .failed:     "Transaction Failed"
        }
    }

    var title: String {
        switch displayState {
        case .processing: "This Will Take a Minute"
        case .success:    "\(currencyName) Is Live"
        case .failed:     "Something Went Wrong"
        }
    }

    var subtitle: String {
        switch displayState {
        case .processing: "This transaction typically takes a few minutes. You may leave the app while it completes"
        case .success:    "Your currency is ready to receive and use"
        case .failed:     "Please try again later"
        }
    }

    var actionTitle: String {
        switch displayState {
        case .processing: "Notify Me When Complete"
        case .success:    "Receive My \(currencyName)"
        case .failed:     "OK"
        }
    }

    var isFinished: Bool { displayState != .processing }
    var isSuccess: Bool  { displayState == .success }

    var analyticsEvent: Analytics.CurrencyLaunchEvent {
        switch fundingMethod {
        case .reserves: .launchWithReserves
        case .phantom:  .launchWithPhantom
        case .coinbase: .launchWithCoinbase
        }
    }

    // MARK: - Actions -

    func cancel() {
        displayState = .failed
    }

    // MARK: - Polling -

    func startPolling(client: Client, ownerKeyPair: KeyPair) async {
        guard !isPolling, displayState == .processing else { return }
        isPolling = true

        do {
            let metadata = try await client.pollSwapState(
                swapId: swapId,
                owner: ownerKeyPair,
                maxAttempts: 180
            ) { [weak self] state in
                Task { @MainActor in
                    self?.currentState = state
                }
            }

            switch metadata.state {
            case .finalized:
                displayState = .success
                Analytics.currencyLaunch(event: analyticsEvent, exchangedFiat: launchAmount, successful: true)
            case .failed, .cancelled:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap completed with failure state")
                displayState = .failed
                Analytics.currencyLaunch(event: analyticsEvent, exchangedFiat: launchAmount, successful: false)
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap timed out in intermediate state")
                displayState = .failed
                Analytics.currencyLaunch(event: analyticsEvent, exchangedFiat: launchAmount, successful: false)
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., by SwiftUI during navigation
            // transitions on iOS 18). Don't treat as failure — the view
            // will restart the task if still visible.
        } catch {
            displayState = .failed
            Analytics.currencyLaunch(event: analyticsEvent, exchangedFiat: launchAmount, successful: false, error: error)
        }

        isPolling = false
    }

    // MARK: - Bill handoff -

    /// Fetches verified state for the launched mint so the caller can show
    /// the cash bill. Returns `nil` if the verified state cannot be resolved
    /// in time — caller should dismiss without presenting a bill.
    func prepareBillHandoff(ratesController: RatesController) async -> Session.BillDescription? {
        isReceivingBill = true
        defer { isReceivingBill = false }

        ratesController.ensureMintSubscribed(launchedMint)

        guard let state = await ratesController.awaitVerifiedState(
            for: launchAmount.converted.currencyCode,
            mint: launchedMint
        ) else {
            logger.warning("Verified state unavailable for launched mint; skipping bill handoff", metadata: [
                "mint": "\(launchedMint.base58)"
            ])
            return nil
        }

        return Session.BillDescription(
            kind: .cash,
            exchangedFiat: launchAmount,
            received: true,
            verifiedState: state
        )
    }

    // MARK: - Reporting -

    private func reportLaunchFailure(state: SwapState, reason: String) {
        ErrorReporting.captureError(
            SwapError.failed(state: state),
            reason: reason,
            metadata: [
                "swapId": swapId.publicKey.base58,
                "fundingMethod": "\(fundingMethod)",
                "finalState": "\(state)",
                "mint": launchedMint.base58,
                "amount": launchAmount.converted.formatted(),
            ]
        )
    }
}

// MARK: - DisplayState -

extension CurrencyLaunchProcessingViewModel {
    enum DisplayState {
        case processing
        case success
        case failed
    }

    enum FundingMethod: String {
        case reserves
        case phantom
        case coinbase
    }
}
