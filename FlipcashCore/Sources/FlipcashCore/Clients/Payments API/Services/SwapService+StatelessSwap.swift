//
//  SwapService+StatelessSwap.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore
import SwiftProtobuf

private let logger = Logger(label: "flipcash.swap-service.stateless")

extension SwapService {
    typealias BidirectionalStatelessSwapStream = BidirectionalGRPCStream<
        Ocp_Transaction_V1_StatelessSwapRequest,
        Ocp_Transaction_V1_StatelessSwapResponse
    >

    /// Runs a Coinbase Stable Swapper stateless swap on the user's behalf.
    ///
    /// Used by the on-app-open USDC → USDF sweep: source is the owner's plain
    /// USDC ATA, destination is the owner's USDF VM Deposit ATA (where Geyser
    /// picks the funds up and credits the USDF VM).
    ///
    /// State machine:
    /// 1. Send `Initiate` with `CoinbaseStableSwapperClientParameters` and the
    ///    owner's signature over the serialized request.
    /// 2. Receive `ServerParameters` → build + sign the v0 versioned
    ///    transaction → send `SubmitSignatures`.
    /// 3. Receive `Success(SUBMITTED|FINALIZED)` or `Error`.
    ///
    /// - Parameters:
    ///   - fromMint: Source mint (USDC).
    ///   - toMint: Destination mint (USDF — must have `vmMetadata`).
    ///   - amount: Source quarks to swap.
    ///   - owner: Owner's keypair — signs both the `Initiate` request and the
    ///     on-chain swap transaction.
    func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<StatelessSwapResult, ErrorStatelessSwap>) -> Void
    ) {
        logger.info("Starting stateless swap", metadata: [
            "from": "\(fromMint.address.base58)",
            "to": "\(toMint.address.base58)",
            "amountQuarks": "\(amount.quarks)",
        ])

        // The response handler and the stream-status handler can both want to
        // resolve the call (success on the response side, non-OK close on the
        // status side). Funnel both through a single-shot so the wrapped
        // continuation in `Client+Transaction` never gets resumed twice.
        let resolve = OneShotCompletion(completion)

        guard toMint.vmMetadata != nil else {
            logger.error("Destination mint missing VM metadata", metadata: [
                "symbol": "\(toMint.symbol)",
            ])
            resolve(.failure(.invalidSwap(reasons: [])))
            return
        }

        let reference = BidirectionalStatelessSwapStream()

        reference.open(onResponse: { response in
            switch response.response {
            case .serverParameters(let parameters):
                switch parameters.kind {
                case .stablecoin(let stableServer):
                    guard let serverParameters = StatelessSwapServerParameters(stableServer) else {
                        logger.error("Failed to parse stateless swap server parameters")
                        reference.cancel()
                        resolve(.failure(.unknown))
                        return
                    }

                    let transaction = TransactionBuilder.statelessSwap(
                        serverParameters: serverParameters,
                        owner: owner.publicKey,
                        fromMint: fromMint,
                        toMint: toMint,
                        amount: amount.quarks
                    )

                    let signatures = transaction.signatures(using: owner)
                    let submitSignatures = Ocp_Transaction_V1_StatelessSwapRequest.with {
                        $0.submitSignatures = .with {
                            $0.transactionSignatures = signatures.map { $0.proto }
                        }
                    }

                    reference.sendMessage(submitSignatures)

                    logger.info("Received stateless swap server parameters, submitting signatures", metadata: [
                        "signatureCount": "\(signatures.count)",
                        "blockhash": "\(serverParameters.blockhash.base58)",
                    ])

                case .none:
                    logger.error("Stateless swap server parameters missing kind")
                    reference.cancel()
                    resolve(.failure(.unknown))
                }

            case .success(let success):
                guard let signature = try? Signature(success.transactionSignature.value) else {
                    logger.error("Stateless swap success missing valid signature")
                    reference.cancel()
                    resolve(.failure(.unknown))
                    return
                }

                let outcome: StatelessSwapResult
                switch success.code {
                case .submitted:
                    outcome = .submitted(signature: signature)
                case .finalized:
                    outcome = .finalized(signature: signature)
                case .UNRECOGNIZED:
                    logger.error("Stateless swap success returned unrecognized code")
                    reference.cancel()
                    resolve(.failure(.unknown))
                    return
                }

                logger.info("Stateless swap success", metadata: [
                    "code": "\(success.code)",
                    "signature": "\(signature.base58)",
                ])

                reference.cancel()
                resolve(.success(outcome))

            case .error(let error):
                logger.error("Stateless swap stream error", metadata: [
                    "code": "\(error.code)",
                    "detailCount": "\(error.errorDetails.count)",
                    "reasons": "\(error.errorDetails.reasonStrings)",
                ])

                reference.cancel()
                resolve(.failure(ErrorStatelessSwap(error: error)))

            case .none:
                logger.error("Stateless swap received empty response from server")
                reference.cancel()
                resolve(.failure(.unknown))
            }
        }, onComplete: { result in
            switch result {
            case .success:
                logger.info("Stateless swap stream closed")

            case .failure(let error as RPCError):
                logger.warning("Stateless swap stream closed with non-OK status", metadata: [
                    "code": "\(error.code)",
                    "message": "\(error.message)",
                ])
                resolve(.failure(.grpcStatus(error)))

            case .failure(let error):
                logger.error("Stateless swap stream closed with gRPC error", metadata: [
                    "error": "\(error)",
                ])
                resolve(.failure(.grpcError(error)))
            }
        }) { requests, onResponse in
            try await self.service.statelessSwap(
                requestProducer: { writer in
                    for await request in requests {
                        try await writer.write(request)
                    }
                },
                onResponse: { streamResponse in
                    for try await message in streamResponse.messages {
                        onResponse(message)
                    }
                }
            )
        }

        // Send Initiate. The signature signs the serialized form of the
        // Initiate message itself (with the signature field still empty at
        // serialization time, per `SwiftProtobuf.Message.sign(with:)`).
        let initiate = Ocp_Transaction_V1_StatelessSwapRequest.with {
            $0.initiate = .with {
                $0.kind = .stablecoin(.with {
                    $0.fromMint = fromMint.address.solanaAccountID
                    $0.toMint = toMint.address.solanaAccountID
                    $0.swapAmount = amount.quarks
                })
                $0.owner = owner.publicKey.solanaAccountID
                $0.waitForFinalization = true
                $0.signature = $0.sign(with: owner)
            }
        }

        reference.sendMessage(initiate)
    }
}

/// Wraps an async completion so it can only fire once. Used to funnel the
/// response handler and the stream-status handler into the same `Result`
/// without double-resuming the upstream continuation.
private final class OneShotCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Result<StatelessSwapResult, ErrorStatelessSwap>) -> Void)?

    init(_ completion: @escaping @Sendable (Result<StatelessSwapResult, ErrorStatelessSwap>) -> Void) {
        self.completion = completion
    }

    func callAsFunction(_ result: Result<StatelessSwapResult, ErrorStatelessSwap>) {
        lock.lock()
        let pending = completion
        completion = nil
        lock.unlock()
        pending?(result)
    }
}
