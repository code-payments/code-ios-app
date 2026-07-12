//
//  AddMoneyProcessingViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.add-money-processing")

/// Settlement surface the processing view model observes: the current USDF
/// balance and a balance-only server refresh. The poll deliberately avoids
/// the full `updatePostTransaction()` fan-out (limits + history sync) — the
/// host screen runs that once on success.
@MainActor
protocol AddMoneySettling: AnyObject {
    func balance(for mint: PublicKey) -> StoredBalance?
    func updateBalance()
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

    /// Onramp fees deliver slightly less than the requested amount, so accept
    /// a small shortfall rather than poll forever for the exact figure.
    private static let completionTolerance: Decimal = 0.98

    private let input: AddMoneyProcessingInput
    private let pollInterval: Duration
    private let timeout: Duration

    private var requiredDelta: FiatAmount {
        input.amount.usdfValue * Self.completionTolerance
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

    /// Drives settlement until the USDF balance rises by roughly the deposited
    /// amount, then flips `displayState`. `performSweep`'s result is advisory —
    /// the balance-rise poll is the authoritative completion signal.
    func run(settlement: any AddMoneySettling, performSweep: @MainActor () async -> Bool) async {
        guard displayState == .processing else { return }

        let baseline = settlement.balance(for: .usdf)?.usdf ?? .zero(in: .usd)
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
            settlement.updateBalance()

            if let current = settlement.balance(for: .usdf)?.usdf, current >= target {
                logger.info("Add money settled", metadata: [
                    "method": "\(input.method)",
                    "baseline": "\(baseline)",
                    "current": "\(current)",
                    "depositRef": "\(input.depositRef ?? "nil")",
                ])
                displayState = .success
                Analytics.addMoney(method: input.method, exchangedFiat: input.amount, successful: true, error: nil)
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
            "depositRef": "\(input.depositRef ?? "nil")",
        ])
        displayState = .failed
        Analytics.addMoney(
            method: input.method,
            exchangedFiat: input.amount,
            successful: false,
            error: SettlementError.deliveryTimedOut
        )
    }

    /// The USDF credit never arrived within the poll deadline.
    private enum SettlementError: Error {
        case deliveryTimedOut
    }
}
