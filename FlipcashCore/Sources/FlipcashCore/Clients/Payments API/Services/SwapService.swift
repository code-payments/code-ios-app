//
//  SwapService.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import Combine
import GRPC
import SwiftProtobuf
import NIO

private let logger = Logger(label: "flipcash.swap-service")

/// Service for managing token swap operations
final class SwapService: CodeService<Ocp_Transaction_V1_TransactionNIOClient>, @unchecked Sendable {
    typealias BidirectionalSwapStream = BidirectionalStreamReference<Ocp_Transaction_V1_StatefulSwapRequest, Ocp_Transaction_V1_StatefulSwapResponse>
    
    // MARK: - Swap -

    /// Swap initiates the swap process by coordinating verified metadata with the server.
    /// This establishes the swap state and reserves blockchain resources (nonce + blockhash).
    ///
    /// - Parameters:
    ///   - swapId: Unique identifier for this swap
    ///   - direction: Buy or sell direction with mint metadata
    ///   - amount: Amount to swap in quarks
    ///   - fundingSource: How the swap will be funded (.submitIntent or .externalWallet)
    ///   - owner: The owner's keypair for signing
    ///   - completion: Callback with result
    func swap(
        swapId: SwapId,
        direction: SwapDirection,
        amount: Quarks,
        fundingSource: FundingSource,
        owner: KeyPair,
        isNewCurrencyLaunch: Bool = false,
        completion: @escaping (Result<SwapMetadata, ErrorSwap>) -> Void
    ) {
        let fromMint = direction.sourceMint.address
        let toMint = direction.destinationMint.address
        logger.info("Starting swap", metadata: [
            "swapId": "\(swapId.publicKey.base58)",
            "from": "\(fromMint.base58)",
            "to": "\(toMint.base58)",
            "amount": "\(amount.formatted())",
            "isNewCurrencyLaunch": "\(isNewCurrencyLaunch)"
        ])

        // New-currency launches defer VM/launchpad metadata validation: the
        // target mint and its VM don't exist yet on-chain. For all other flows,
        // we validate that the mints have VM + launchpad metadata hydrated.
        if !isNewCurrencyLaunch {
            switch direction {
            case .buy(let targetMint):
                guard targetMint.vmMetadata != nil else {
                    logger.error("Target mint missing VM metadata", metadata: [
                        "symbol": "\(targetMint.symbol)",
                        "mint": "\(targetMint.address.base58)"
                    ])
                    completion(.failure(.invalidSwap))
                    return
                }
                guard targetMint.launchpadMetadata != nil else {
                    logger.error("Target mint missing launchpad metadata", metadata: [
                        "symbol": "\(targetMint.symbol)",
                        "mint": "\(targetMint.address.base58)"
                    ])
                    completion(.failure(.invalidSwap))
                    return
                }
            case .sell(let sourceMint):
                guard sourceMint.vmMetadata != nil else {
                    logger.error("Source mint missing VM metadata", metadata: [
                        "symbol": "\(sourceMint.symbol)",
                        "mint": "\(sourceMint.address.base58)"
                    ])
                    completion(.failure(.invalidSwap))
                    return
                }
                guard sourceMint.launchpadMetadata != nil else {
                    logger.error("Source mint missing launchpad metadata", metadata: [
                        "symbol": "\(sourceMint.symbol)",
                        "mint": "\(sourceMint.address.base58)"
                    ])
                    completion(.failure(.invalidSwap))
                    return
                }
            }
        }

        // Also validate that USDF (core mint) has VM metadata
        guard MintMetadata.usdf.vmMetadata != nil else {
            logger.error("USDF missing VM metadata")
            completion(.failure(.invalidSwap))
            return
        }

        let reference = BidirectionalSwapStream()
        let queue = self.queue // Capture queue, not self

        // Store client parameters for verification metadata construction
        let clientParameters = VerifiedSwapMetadata.ClientParameters(
            id: swapId,
            fromMint: fromMint,
            toMint: toMint,
            amount: amount,
            fundingSource: fundingSource
        )

        // Intentionally creates a retain-cycle using closures to ensure that we have
        // a strong reference to the stream at all times. Doing so ensures that the
        // callers don't have to manage the pointer to this stream and keep it alive
        reference.retain()

        // Swap authority signs the transaction. For standard swaps the server
        // requires a distinct authority from owner; for new-currency launches
        // the server requires owner == swap_authority.
        let swapAuthority: KeyPair = isNewCurrencyLaunch ? owner : (KeyPair.generate() ?? owner)

        // Store server parameters when received
        var receivedServerParameters: VerifiedSwapMetadata.ServerParameters?
        var verifiedMetadataSignature: Signature?

        reference.stream = service.statefulSwap(callOptions: .streaming) { result in
            switch result.response {

                // 2. Upon successful submission of the Start message, server will
                // respond with parameters (nonce + blockhash) that we need to sign
            case .serverParameters(let parameters):
                switch parameters.kind {
                case .reserveExistingCurrency(let serverParams):
                    guard let serverParameters = VerifiedSwapMetadata.ServerParameters(serverParams) else {
                        logger.error("Failed to parse swap server parameters")
                        _ = reference.stream?.sendEnd()
                        completion(.failure(.unknown))
                        return
                    }

                    guard let responseParams = SwapResponseServerParameters(parameters) else {
                        logger.error("Failed to parse swap response parameters")
                        _ = reference.stream?.sendEnd()
                        completion(.failure(.unknown))
                        return
                    }

                    // Store for later use in success response
                    receivedServerParameters = serverParameters

                    // Construct verified metadata for signing
                    let verifiedMetadata = VerifiedSwapMetadata(
                        clientParameters: clientParameters,
                        serverParameters: serverParameters
                    )

                    // Build the swap transaction and sign with both owner and swapAuthority
                    let transaction = TransactionBuilder.swap(
                        responseParams: responseParams,
                        metadata: verifiedMetadata,
                        authority: owner.publicKey,
                        swapAuthority: swapAuthority.publicKey,
                        direction: direction,
                        amount: amount.quarks
                    )
                    let signatures = transaction.signatures(using: owner, swapAuthority)
                    verifiedMetadataSignature = signatures.first

                    // Send both signatures back to server
                    let submitSignature = Ocp_Transaction_V1_StatefulSwapRequest.with {
                        $0.submitSignatures = .with {
                            $0.transactionSignatures = signatures.map { $0.proto }
                        }
                    }

                    _ = reference.stream?.sendMessage(submitSignature)

                    logger.info("Received swap server parameters, submitting signatures", metadata: [
                        "signatureCount": "\(signatures.count)",
                        "nonce": "\(serverParameters.nonce.base58)",
                        "blockhash": "\(serverParameters.blockhash.base58)"
                    ])

                case .reserveNewCurrency(let serverParams):
                    guard let params = SwapResponseServerParameters.ReserveNewCurrency(serverParams) else {
                        logger.error("Failed to parse new-currency server parameters")
                        _ = reference.stream?.sendEnd()
                        completion(.failure(.unknown))
                        return
                    }

                    // Verify that the mint derived from server params matches
                    // the mint the client expects (clientParameters.toMint).
                    guard let (derivedMint, _) = LaunchpadMint.deriveMint(
                        authority: params.authority,
                        name: params.name,
                        seed: params.seed
                    ) else {
                        logger.error("Failed to derive mint from new-currency server params")
                        _ = reference.stream?.sendEnd()
                        completion(.failure(.invalidSwap))
                        return
                    }

                    guard derivedMint == clientParameters.toMint else {
                        logger.error("Derived mint does not match expected mint", metadata: [
                            "expected": "\(clientParameters.toMint.base58)",
                            "derived": "\(derivedMint.base58)"
                        ])
                        _ = reference.stream?.sendEnd()
                        completion(.failure(.invalidSwap))
                        return
                    }

                    let serverParameters = VerifiedSwapMetadata.ServerParameters(
                        nonce: params.nonce,
                        blockhash: params.blockhash
                    )
                    receivedServerParameters = serverParameters

                    // Build the atomic launch-and-first-buy transaction. The owner
                    // is also the swap_authority for new-currency flows, so only
                    // one signature is required.
                    let transaction = TransactionBuilder.swapNewCurrency(
                        responseParams: params,
                        authority: owner.publicKey,
                        amount: amount.quarks
                    )

                    // Log the serialized transaction so it can be diffed against
                    // the server's `expected_transaction` when `signatureError`
                    // comes back. `encode()` includes the zero-filled signature
                    // slots + message body, matching the server's expected form.
                    logger.debug("New-currency transaction built", metadata: [
                        "txBytes": "\(transaction.encode().hexEncodedString())"
                    ])

                    let signatures = transaction.signatures(using: owner)
                    verifiedMetadataSignature = signatures.first

                    let submitSignature = Ocp_Transaction_V1_StatefulSwapRequest.with {
                        $0.submitSignatures = .with {
                            $0.transactionSignatures = signatures.map { $0.proto }
                        }
                    }

                    _ = reference.stream?.sendMessage(submitSignature)

                    logger.info("New-currency swap submitting signatures", metadata: [
                        "signatureCount": "\(signatures.count)",
                        "mint": "\(derivedMint.base58)",
                        "nonce": "\(params.nonce.base58)",
                        "blockhash": "\(params.blockhash.base58)"
                    ])

                case .none:
                    logger.error("Unexpected empty server parameter kind in swap")
                    _ = reference.stream?.sendEnd()
                    completion(.failure(.unknown))
                }

                // 3. If submitted signature is valid, we'll receive a success
                // and the swap state will be created on the server
            case .success:
                guard let serverParams = receivedServerParameters,
                      let signature = verifiedMetadataSignature else {
                    logger.error("Swap success received but missing server parameters or signature")
                    _ = reference.stream?.sendEnd()
                    completion(.failure(.unknown))
                    return
                }
                
                let metadata = SwapMetadata(
                    verifiedMetadata: VerifiedSwapMetadata(
                        clientParameters: clientParameters,
                        serverParameters: serverParams
                    ),
                    state: .created,
                    signature: signature
                )
                
                logger.info("Swap started successfully", metadata: ["swapId": "\(swapId.publicKey.base58)"])
                _ = reference.stream?.sendEnd()
                completion(.success(metadata))
                
                // 3. If the submitted signature is invalid or other error occurs
            case .error(let error):
                var container: [String] = []
                container.append("Code: \(error.code)")
                
                let errors = error.errorDetails.flatMap { details -> [String] in
                    switch details.type {
                    case .reasonString(let reason):
                        return ["Reason: \(reason.reason)"]

                    case .invalidSignature(let signatureDetails):
                        return [
                            "Action index: \(signatureDetails.actionID)",
                            "Invalid signature: \((try? Signature(signatureDetails.providedSignature.value).base58) ?? "nil")",
                            "Transaction bytes: \(signatureDetails.expectedTransaction.value.hexEncodedString())",
                        ]

                    case .denied(let deniedDetails):
                        var parts = ["Denied code: \(deniedDetails.code)"]
                        if !deniedDetails.reason.isEmpty {
                            parts.append("Denied reason: \(deniedDetails.reason)")
                        }
                        return parts

                    case .none:
                        return []
                    }
                }
                container.append(contentsOf: errors)

                logger.error("Swap stream error", metadata: [
                    "code": "\(error.code)",
                    "detailCount": "\(error.errorDetails.count)",
                    "details": "\(container.joined(separator: " | "))"
                ])

                _ = reference.stream?.sendEnd()
                let intentError = ErrorSwap(error: error)
                completion(.failure(intentError))

            case .none:
                logger.error("Swap received empty response from server")
                _ = reference.stream?.sendEnd()
                completion(.failure(.unknown))
            }
        }

        reference.stream?.status.whenCompleteBlocking(onto: queue) { result in
            switch result {
            case .success(let status):
                if status.code == .ok {
                    logger.info("Swap stream closed")
                    // Completion called in the success block
                } else {
                    logger.warning("Swap stream closed with non-OK status", metadata: [
                        "code": "\(status.code)",
                        "message": "\(status.message ?? "nil")"
                    ])
                    completion(.failure(.grpcStatus(status)))
                }

            case .failure(let error):
                logger.error("Swap stream closed with gRPC error", metadata: ["error": "\(error)"])
                completion(.failure(.grpcError(error)))
            }
            
            // We release the stream reference after the stream has been
            // closed and there's no further actions required
            reference.release()
        }
        
        // 1. Send `Start` request with client parameters
        // (swapAuthority is generated above for use in both the Initiate and ServerParameters handling)

        // The server requires a proof signature with the Initiate request.
        // The proof signature must sign the full VerifiedSwapMetadata proto,
        // which wraps the client parameters in:
        //   VerifiedSwapMetadata { currency_creator { client_parameters = ... } }
        do {
            let clientProto = clientParameters.proto

            // Build the full VerifiedSwapMetadata proto structure
            let verifiedMetadataProto = Ocp_Transaction_V1_VerifiedSwapMetadata.with {
                $0.reserve = .with {
                    $0.clientParameters = clientProto
                }
            }
            let serialized = try verifiedMetadataProto.serializedData()
            let proof = owner.sign(serialized)

            let startRequest = Ocp_Transaction_V1_StatefulSwapRequest.with {
                $0.initiate = .with {
                    $0.kind = .reserve(clientProto)
                    $0.owner = owner.publicKey.solanaAccountID
                    $0.swapAuthority = swapAuthority.publicKey.solanaAccountID
                    $0.proofSignature = proof.proto
                    $0.signature = $0.sign(with: owner)
                }
            }

            _ = reference.stream?.sendMessage(startRequest)
        } catch {
            logger.error("Failed to serialize client parameters for proof signature", metadata: ["error": "\(error)"])
            _ = reference.stream?.sendEnd()
            completion(.failure(.unknown))
            return
        }
    }

    // MARK: - GetSwap -

    /// Fetches the current state of a swap by its ID.
    ///
    /// - Parameters:
    ///   - swapId: The unique identifier of the swap
    ///   - owner: The owner's keypair for authentication
    ///   - completion: Callback with result containing SwapMetadata or ErrorGetSwap
    func getSwap(
        swapId: SwapId,
        owner: KeyPair,
        completion: @escaping (Result<SwapMetadata, ErrorGetSwap>) -> Void
    ) {
        logger.info("Fetching swap state", metadata: ["swapId": "\(swapId.publicKey.base58)"])

        var request = Ocp_Transaction_V1_GetSwapRequest()
        request.id = swapId.codeSwapID
        request.owner = owner.publicKey.solanaAccountID
        request.signature = request.sign(with: owner)

        let call = service.getSwap(request)

        call.response.whenCompleteBlocking(onto: queue) { result in
            switch result {
            case .success(let response):
                switch response.result {
                case .ok:
                    guard let metadata = SwapMetadata(response.swap) else {
                        logger.error("Failed to parse swap metadata")
                        completion(.failure(.failedToParse))
                        return
                    }
                    logger.info("Swap state fetched", metadata: ["state": "\(metadata.state)"])
                    completion(.success(metadata))

                case .notFound:
                    // Expected during the early phase of polling a freshly
                    // submitted swap; the caller retries on this condition.
                    logger.debug("Swap not found")
                    completion(.failure(.notFound))

                case .denied:
                    logger.error("Swap access denied")
                    completion(.failure(.denied))

                case .UNRECOGNIZED:
                    logger.error("Swap fetch returned unknown result")
                    completion(.failure(.unknown))
                }

            case .failure(let error):
                logger.error("Swap fetch gRPC error", metadata: ["error": "\(error)"])
                completion(.failure(.unknown))
            }
        }
    }
}

// MARK: - Types -

public enum SwapResult: Sendable {
    case finalized
    case submitted
}

public enum ErrorSwap: Error, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    /// Proto-code-backed denial reason. Maps 1:1 to DeniedErrorDetails.Code.
    public enum DeniedReason: Int, Sendable {
        /// No reason is available
        case unspecified // = 0
    }

    /// Semantic categorization derived from the server's human-readable reason string.
    /// Independent of the proto code — extended whenever we want to handle a
    /// specific server message specially at a call site.
    public enum DeniedKind: Sendable, Equatable {
        /// The swap amount is too small to produce a non-zero sell fee.
        /// Server reason: "swap would not generate a sell fee"
        case insufficientSellFee

        public init?(serverReason: String) {
            if serverReason.range(of: "would not generate a sell fee", options: .caseInsensitive) != nil {
                self = .insufficientSellFee
                return
            }
            return nil
        }
    }

    case denied([DeniedReason], kinds: Set<DeniedKind>, messages: [String])
    case signatureError
    case invalidSwap
    case failed
    case unknown
    case grpcStatus(GRPCStatus)
    /// gRPC error
    case grpcError(Error)

    init(error: Ocp_Transaction_V1_StatefulSwapResponse.Error) {
        switch error.code {
        case .denied:
            var reasons: [DeniedReason] = []
            var kinds: Set<DeniedKind> = []
            var messages: [String] = []
            for details in error.errorDetails {
                if case .denied(let deniedDetails) = details.type {
                    if let reason = DeniedReason(rawValue: deniedDetails.code.rawValue) {
                        reasons.append(reason)
                    }
                    if let kind = DeniedKind(serverReason: deniedDetails.reason) {
                        kinds.insert(kind)
                    }
                    if !deniedDetails.reason.isEmpty {
                        messages.append(deniedDetails.reason)
                    }
                }
            }
            self = .denied(reasons, kinds: kinds, messages: messages)

        case .invalidSwap:
            self = .invalidSwap
        case .signatureError:
            self = .signatureError

        case .UNRECOGNIZED:
            self = .unknown
        }
    }

    public var description: String {
        switch self {
        case .denied(let reasons, _, let messages):
            let reasonString = reasons.map { "\($0)" }.joined(separator: ", ")
            if messages.isEmpty {
                return "denied(\(reasonString))"
            }
            return "denied(\(reasonString): \(messages.joined(separator: "; ")))"
        case .signatureError:
            return "signatureError"
        case .invalidSwap:
            return "invalidSwap"
        case .failed:
            return "failed"
        case .unknown:
            return "unknown"
        case .grpcStatus(let status):
            return "grpcStatus(\(status.code.rawValue))"
        case .grpcError(let error):
            return "grpcError(\(error.localizedDescription))"
        }
    }
    
    public var debugDescription: String {
        description
    }
}

public enum ErrorGetSwap: Int, Error {
    case ok
    case notFound
    case denied
    case unknown = -1
    case failedToParse = -2
}
