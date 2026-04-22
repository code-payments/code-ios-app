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

    func startPolling(client: Client, session: Session, ratesController: RatesController) async {
        guard !isPolling, displayState == .processing else { return }
        isPolling = true

        // Subscribe the launched mint to the live streamer before we start
        // polling its balance. Without this, `awaitBalance` polls an in-memory
        // channel the streamer is never writing to, and the balance only
        // arrives when an unrelated server push (activity fetch) happens to
        // refresh the subscription list. Subscribing here makes the stream
        // deliver the balance directly, cutting the wait from ~70s → a few.
        ratesController.ensureMintSubscribed(launchedMint)

        do {
            let metadata = try await client.pollSwapState(
                swapId: swapId,
                owner: session.ownerKeyPair,
                maxAttempts: 120
            ) { [weak self] state in
                Task { @MainActor in
                    self?.currentState = state
                }
            }

            switch metadata.state {
            case .finalized:
                // Swap settled on-chain. The streamer is already subscribed
                // (see top of this function), so the balance/supply update
                // typically arrives within a few seconds. Gate success on
                // the real balance landing so the "Receive My X" handoff
                // doesn't race the streamed wallet update.
                if await awaitBalance(session: session) {
                    displayState = .success
                    Analytics.currencyLaunch(event: analyticsEvent, launchedMint: launchedMint, exchangedFiat: launchAmount, successful: true)
                } else {
                    reportLaunchFailure(state: metadata.state, reason: "Launched currency balance did not land within budget")
                    displayState = .failed
                    Analytics.currencyLaunch(event: analyticsEvent, launchedMint: launchedMint, exchangedFiat: launchAmount, successful: false)
                }
            case .failed, .cancelled:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap completed with failure state")
                displayState = .failed
                Analytics.currencyLaunch(event: analyticsEvent, launchedMint: launchedMint, exchangedFiat: launchAmount, successful: false)
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap timed out in intermediate state")
                displayState = .failed
                Analytics.currencyLaunch(event: analyticsEvent, launchedMint: launchedMint, exchangedFiat: launchAmount, successful: false)
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., by SwiftUI during navigation
            // transitions on iOS 18). Don't treat as failure — the view
            // will restart the task if still visible.
        } catch {
            displayState = .failed
            Analytics.currencyLaunch(event: analyticsEvent, launchedMint: launchedMint, exchangedFiat: launchAmount, successful: false, error: error)
        }

        isPolling = false
    }

    /// Polls `session.balance(for: launchedMint)` until the launched currency
    /// has fully materialised — both non-zero `quarks` and bonding supply
    /// populated. Budget: 60 × 2 s = 2 min. With proactive subscription in
    /// `startPolling`, the stream typically delivers within a few seconds,
    /// so 2 min is generous headroom for slow-server conditions.
    ///
    /// Checking only for presence is insufficient: the stream can land a
    /// zero-quarks entry before the real balance/supply values follow,
    /// which causes downstream bill creation to build a $0 bill that the
    /// server rejects with "Quarks must be greater than 0".
    private func awaitBalance(session: Session, maxAttempts: Int = 60, interval: Duration = .seconds(2)) async -> Bool {
        for i in 0..<maxAttempts {
            if Task.isCancelled { return false }
            if i > 0 {
                try? await Task.sleep(for: interval)
            }
            if let stored = session.balance(for: launchedMint),
               stored.quarks > 0,
               stored.supplyFromBonding != nil {
                logger.info("Launched currency balance landed", metadata: [
                    "mint": "\(launchedMint.base58)",
                    "attempt": "\(i + 1)/\(maxAttempts)",
                    "quarks": "\(stored.quarks)",
                ])
                return true
            }
            // Heartbeat every 5 attempts (~10s) so the console isn't silent
            // for minutes if the stream stalls.
            if i > 0 && i % 5 == 0 {
                logger.debug("Awaiting launched currency balance", metadata: [
                    "mint": "\(launchedMint.base58)",
                    "attempt": "\(i + 1)/\(maxAttempts)",
                ])
            }
        }
        logger.warning("Launched currency balance did not materialise in budget", metadata: [
            "mint": "\(launchedMint.base58)",
            "maxAttempts": "\(maxAttempts)",
        ])
        return false
    }

    // MARK: - Bill handoff -

    /// Builds the cash-bill description for the newly-created currency. The
    /// bill represents the user's *launched-currency* balance, not the USDF
    /// they spent — otherwise `SendCashOperation` derives USDF timelock
    /// accounts and the launchpad reserve proof gets rejected with
    /// "reserve state cannot be provided for core mint". Returns `nil` when
    /// the verified state or balance are unexpectedly missing (the polling
    /// loop should have guaranteed both by now).
    func prepareBillHandoff(session: Session, ratesController: RatesController) async -> Session.BillDescription? {
        isReceivingBill = true
        defer { isReceivingBill = false }

        ratesController.ensureMintSubscribed(launchedMint)

        // Launch bills are always USD — the entire launch flow is USD-anchored
        // (purchase + fee come from `userFlags` in USDF quarks and the wizard
        // renders them as USD). Forcing USD here also eliminates the
        // rate-drift class of the "native amount does not match expected sell
        // value" bug: `.oneToOne` is trivially consistent with any USD proof.
        guard let state = await ratesController.awaitVerifiedState(
            for: .usd,
            mint: launchedMint
        ) else {
            logger.warning("Verified state unavailable for launched mint; skipping bill handoff", metadata: [
                "mint": "\(launchedMint.base58)"
            ])
            return nil
        }

        guard let stored = session.balance(for: launchedMint),
              stored.quarks > 0,
              stored.supplyFromBonding != nil else {
            logger.warning("Launched currency balance missing or not materialised at handoff; skipping bill", metadata: [
                "mint": "\(launchedMint.base58)"
            ])
            return nil
        }

        // Use the proof's supply so `quarks × bondingCurve.sell(..., supply)`
        // on both client and server agree. The rate is `.oneToOne` — USD/USDF
        // carry no FX drift.
        let proofSupply = state.supplyFromBonding ?? stored.supplyFromBonding
        let balanceFiat = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: stored.quarks, mint: launchedMint),
            rate: .oneToOne,
            supplyQuarks: proofSupply
        )

        guard balanceFiat.onChainAmount.quarks > 0 else {
            logger.warning("Launched currency bill computed to zero fiat; skipping bill", metadata: [
                "mint": "\(launchedMint.base58)",
                "storedQuarks": "\(stored.quarks)",
            ])
            return nil
        }

        return Session.BillDescription(
            kind: .cash,
            exchangedFiat: balanceFiat,
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
                "amount": launchAmount.nativeAmount.formatted(),
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
