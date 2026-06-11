//
//  ReservesFundingOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

private let logger = Logger(label: "flipcash.reserves-funding")

/// Funds a buy or launch out of the user's USDF balance ("reserves"). No
/// external sign, no overlay UI — the simplest concrete `FundingOperation`.
///
/// `.buy` calls `purchases.buy(...)` directly. `.launch` calls
/// `purchases.launchCurrency(...)` followed by `purchases.buyNewCurrency(...)`,
/// using the verifiedState pinned by the wizard at submission time.
@Observable
final class ReservesFundingOperation: FundingOperation {

    private(set) var state: FundingOperationState = .idle
    let requirements: [FundingRequirement] = []

    /// Set after the launch RPC succeeds (only meaningful for `.launch`
    /// flows). Lets callers recover the just-minted PublicKey when the
    /// subsequent `buyNewCurrency` step throws — without it, a retry would
    /// re-launch and hit `nameExists`.
    private(set) var launchedMint: PublicKey?

    @ObservationIgnored private let purchases: any (ReservesBuying & CurrencyLaunching)
    @ObservationIgnored private var runTask: Task<StartedSwap, Error>?

    init(purchases: any (ReservesBuying & CurrencyLaunching)) {
        self.purchases = purchases
    }

    isolated deinit {
        runTask?.cancel()
    }

    func start(_ operation: PaymentOperation) async throws -> StartedSwap {
        let task = Task { try await run(operation) }
        runTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// No user-action steps — `start()` runs straight through.
    func confirm() {}

    func cancel() {
        runTask?.cancel()
    }

    private func run(_ operation: PaymentOperation) async throws -> StartedSwap {
        state = .working
        defer { state = .idle }

        switch operation {
        case .buy(let payload):
            let swapId = try await purchases.buy(
                amount: payload.amount,
                verifiedState: payload.verifiedState,
                of: payload.mint
            )
            return StartedSwap(
                swapId: swapId,
                swapType: .buyWithReserves,
                currencyName: payload.currencyName,
                amount: payload.amount,
                launchedMint: nil
            )

        case .launch(let payload):
            guard let verifiedState = payload.verifiedState else {
                logger.error("Reserves launch invoked without a verified state")
                throw FundingOperationError.unexpectedFailure(reason: "Missing verified state")
            }

            let mint: PublicKey
            // Retry from a prior attempt whose launch already succeeded —
            // skip the launch RPC so the server doesn't return `nameExists`.
            if let preLaunched = payload.preLaunchedMint {
                mint = preLaunched
            } else {
                guard let attestations = payload.attestations else {
                    logger.error("Reserves launch invoked without attestations")
                    throw FundingOperationError.unexpectedFailure(reason: "Missing launch attestations")
                }
                mint = try await purchases.launchCurrency(
                    name: payload.currencyName,
                    description: attestations.description,
                    billColors: attestations.billColors,
                    icon: attestations.icon,
                    nameAttestation: attestations.nameAttestation,
                    descriptionAttestation: attestations.descriptionAttestation,
                    iconAttestation: attestations.iconAttestation
                )
            }
            launchedMint = mint

            let swapId = try await purchases.buyNewCurrency(
                amount: payload.launchAmount,
                feeAmount: payload.launchFee,
                verifiedState: verifiedState,
                mint: mint,
                swapId: .generate()
            )

            return StartedSwap(
                swapId: swapId,
                swapType: .launchWithReserves,
                currencyName: payload.currencyName,
                amount: payload.launchAmount,
                launchedMint: mint
            )
        }
    }
}
