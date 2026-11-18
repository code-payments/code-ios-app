//
//  CurrencyLaunchProcessingViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.currency-launch-processing")

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
    /// The token that paid the launch cost — distinguishes the reserves and
    /// currency analytics events.
    let paymentMint: PublicKey

    // MARK: - Private -

    private let swapId: SwapId
    /// One-second polls' worth of the inline window already spent on the wizard, deducted from the swap budget here.
    private let attemptsUsed: Int

    /// Total slow-path swap poll budget, one poll per second.
    static let maxSwapAttempts = 120

    /// Total balance poll budget, one poll per `balancePollInterval`.
    static let maxBalanceAttempts = 60
    static let balancePollInterval: Duration = .seconds(2)

    /// Balance polls left once the inline window's time is deducted.
    var remainingBalanceAttempts: Int {
        let spent = Int(Duration.seconds(attemptsUsed) / Self.balancePollInterval)
        return max(1, Self.maxBalanceAttempts - spent)
    }

    // MARK: - Init -

    init(swapId: SwapId, launchedMint: PublicKey, currencyName: String, launchAmount: ExchangedFiat, paymentMint: PublicKey, attemptsUsed: Int = 0) {
        self.attemptsUsed = attemptsUsed
        self.swapId = swapId
        self.launchedMint = launchedMint
        self.currencyName = currencyName
        self.launchAmount = launchAmount
        self.paymentMint = paymentMint
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
        case .processing: "This Will Take a Few Minutes"
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
        case .success:    "Get The First \(launchAmount.nativeAmount.formatted(minimumFractionDigits: 0)) of Your Currency Free"
        case .failed:     "OK"
        }
    }

    var isFinished: Bool { displayState != .processing }
    var isSuccess: Bool  { displayState == .success }

    var launchMethod: LaunchMethod {
        paymentMint == .usdf ? .reserves : .currency
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
                maxAttempts: max(1, Self.maxSwapAttempts - attemptsUsed)
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
                if await awaitBalance(session: session, maxAttempts: remainingBalanceAttempts) {
                    displayState = .success
                    trackLaunch(successful: true)
                } else {
                    reportLaunchFailure(state: metadata.state, reason: "Launched currency balance did not land within budget")
                    displayState = .failed
                    trackLaunch(successful: false)
                }
            case .failed, .cancelled:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap completed with failure state")
                displayState = .failed
                trackLaunch(successful: false)
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap timed out in intermediate state")
                displayState = .failed
                trackLaunch(successful: false)
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., by SwiftUI during navigation
            // transitions on iOS 18). Don't treat as failure — the view
            // will restart the task if still visible.
        } catch let error as ClientError where error.isSwapPollRefusal {
            reportLaunchPollRefusal(error)
            displayState = .failed
            trackLaunch(successful: false, error: error)
        } catch {
            // No swap state was ever fetched within the poll budget
            logger.error("Launch swap polling failed", metadata: ["error": "\(error)"])
            displayState = .failed
            trackLaunch(successful: false, error: error)
        }

        isPolling = false
    }

    // MARK: - Inline polling -

    /// Waits for the launch on the wizard that submitted it, covering the swap poll and the
    /// balance check in one shared inline window. Terminal results are reported; `.pending`
    /// means this view model should be handed to the processing screen to continue.
    func awaitInline(
        session: Session,
        ratesController: RatesController,
        poll: SwapPoller? = nil
    ) async -> InlineSwapCompletion.Outcome {
        ratesController.ensureMintSubscribed(launchedMint)

        let clock = ContinuousClock()
        let deadline = clock.now + InlineCompletion.window
        let swapId = swapId
        let poll = poll ?? { attempts, interval in
            try await session.pollSwapState(swapId: swapId, maxAttempts: attempts, interval: interval)
        }

        do {
            let metadata = try await poll(InlineCompletion.maxAttempts, InlineCompletion.pollInterval)
            switch metadata.state {
            case .finalized:
                let remaining = max(1, Int(((deadline - clock.now) / InlineCompletion.pollInterval).rounded(.up)))
                guard await awaitBalance(session: session, maxAttempts: remaining, interval: InlineCompletion.pollInterval) else {
                    return .pending
                }
                displayState = .success
                trackLaunch(successful: true)
                return .succeeded
            case .failed, .cancelled:
                reportLaunchFailure(state: metadata.state, reason: "Launch swap completed with failure state")
                displayState = .failed
                trackLaunch(successful: false)
                return .failed
            case .unknown, .created, .funding, .funded, .submitting, .cancelling:
                return .pending
            }
        } catch is CancellationError {
            // Already submitted; the processing screen resumes polling rather than risking a resubmit.
            return .pending
        } catch ClientError.pollLimitReached {
            return .pending
        } catch let error as ClientError where error.isSwapPollRefusal {
            reportLaunchPollRefusal(error)
            displayState = .failed
            trackLaunch(successful: false, error: error)
            return .failed
        } catch {
            logger.error("Launch swap polling failed", metadata: ["error": "\(error)"])
            displayState = .failed
            trackLaunch(successful: false, error: error)
            return .failed
        }
    }

    /// Builds the bill for the new currency, dismisses the flow, then shows the bill once the
    /// dismiss animation has finished.
    func receiveLaunchedCurrency(
        session: Session,
        ratesController: RatesController,
        dismiss: () -> Void,
        dismissDelay: Duration = AppRouter.dismissAnimationDuration
    ) async {
        let description = await prepareBillHandoff(session: session, ratesController: ratesController)
        dismiss()
        // Wait for the dismiss animation to finish before mutating bill state,
        // so ScanScreen renders the bill as a fresh entrance instead of
        // revealing it underneath the closing sheet.
        try? await Task.sleep(for: dismissDelay)
        if let description {
            session.showCashBill(description)
        }
    }

    private func trackLaunch(successful: Bool, error: Error? = nil) {
        Analytics.currencyLaunch(method: launchMethod, launchedMint: launchedMint, paymentMint: paymentMint, exchangedFiat: launchAmount, successful: successful, error: error)
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
    private func awaitBalance(session: Session, maxAttempts: Int = maxBalanceAttempts, interval: Duration = balancePollInterval) async -> Bool {
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

            logger.debug("Awaiting launched currency balance", metadata: [
                "mint": "\(launchedMint.base58)",
                "attempt": "\(i + 1)/\(maxAttempts)",
            ])
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
            exchangedFiat: balanceFiat,
            received: true,
            verifiedState: state
        )
    }

    // MARK: - Reporting -

    private func reportLaunchPollRefusal(_ error: ClientError) {
        logger.error("Launch swap poll refused", metadata: [
            "swapId": "\(swapId.publicKey.base58)",
            "mint": "\(launchedMint.base58)",
            "error": "\(error)",
        ])
        ErrorReporting.captureError(
            error,
            reason: "Launch swap poll refused by server",
            metadata: [
                "swapId": swapId.publicKey.base58,
                "mint": launchedMint.base58,
                "amount": launchAmount.nativeAmount.formatted(),
            ]
        )
    }

    private func reportLaunchFailure(state: SwapState, reason: String) {
        logger.error("Launch swap failed", metadata: [
            "swapId": "\(swapId.publicKey.base58)",
            "state": "\(state)",
            "mint": "\(launchedMint.base58)",
            "reason": "\(reason)",
        ])
        ErrorReporting.captureError(
            SwapError.failed(state: state),
            reason: reason,
            metadata: [
                "swapId": swapId.publicKey.base58,
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
}
