//
//  AddMoneyProcessingViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.add-money-processing")

/// Narrow settlement surface the processing view model observes: read the
/// current USDF balance and trigger a server balance refresh. `Session`
/// already provides both, so its conformance is a no-op — the protocol exists
/// purely so the state machine is testable with a fake.
@MainActor
protocol AddMoneySettling: AnyObject {
    func balance(for mint: PublicKey) -> StoredBalance?
    func updatePostTransaction()
}

extension Session: AddMoneySettling {}

@Observable
@MainActor
final class AddMoneyProcessingViewModel {

    // MARK: - State

    private(set) var displayState: SwapProcessingViewModel.DisplayState = .processing

    var title: String {
        switch displayState {
        case .processing:
            return "This Will Take a Minute"
        case .success:
            return "\(input.amount.nativeAmount.formatted()) of USDF"
        case .failed:
            return "Something Went Wrong"
        }
    }

    var subtitle: String {
        switch displayState {
        case .processing:
            return "This transaction typically takes about a minute. You may leave the app while it completes"
        case .success:
            return "was added to your Flipcash wallet"
        case .failed:
            return "Please try again later"
        }
    }

    var actionTitle: String {
        switch displayState {
        case .processing:
            return "Notify Me When Complete"
        case .success, .failed:
            return "OK"
        }
    }

    var navigationTitle: String { "Adding Money" }

    var isSuccess: Bool { displayState == .success }
    var isFinished: Bool { displayState != .processing }

    // MARK: - Private

    /// Onramp fees + the USD→USDF rate deliver slightly less than the requested
    /// amount (Coinbase records at ~0.9994), so accept a small shortfall rather
    /// than poll forever waiting for the exact figure.
    private static let completionTolerance: Decimal = 0.98

    private let input: AddMoneyProcessingInput
    private let pollInterval: Duration
    private let timeout: Duration

    private var requiredDelta: Decimal {
        input.amount.usdfValue.value * Self.completionTolerance
    }

    // MARK: - Init

    init(
        input: AddMoneyProcessingInput,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(120)
    ) {
        self.input = input
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    // MARK: - Run

    /// Drives settlement to completion:
    /// - Coinbase / Other Wallet: run the USDC→USDF sweep, then poll for the
    ///   USDF balance to rise by ~the deposited amount.
    /// - Phantom: the tx already carried the USDC→USDF swap, so just poll.
    ///
    /// `performSweep` wraps `UsdcSweepOperation.sweepUntilConverted`; its result
    /// is advisory — the balance-rise poll is the authoritative completion
    /// signal, so a `false` sweep still falls through to the timeout path.
    func run(settlement: any AddMoneySettling, performSweep: @MainActor () async -> Bool) async {
        guard displayState == .processing else { return }

        let baseline = settlement.balance(for: .usdf)?.usdf.value ?? 0
        let target = baseline + requiredDelta

        switch input.method {
        case .coinbase, .otherWallet:
            _ = await performSweep()
        case .phantom:
            break
        }

        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return }
            settlement.updatePostTransaction()

            if let current = settlement.balance(for: .usdf)?.usdf.value, current >= target {
                logger.info("Add money settled", metadata: [
                    "method": "\(input.method)",
                    "baseline": "\(baseline)",
                    "current": "\(current)",
                ])
                displayState = .success
                return
            }

            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return // task cancelled by SwiftUI teardown
            }
        }

        logger.error("Add money timed out waiting for USDF credit", metadata: [
            "method": "\(input.method)",
            "baseline": "\(baseline)",
            "target": "\(target)",
        ])
        displayState = .failed
    }
}
