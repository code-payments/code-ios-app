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
        completion: @escaping (Result<SwapMetadata, ErrorSwap>) -> Void
    ) {
        let fromMint = direction.sourceMint.address
        let toMint = direction.destinationMint.address
        trace(.send, components: "Swap ID: \(swapId.publicKey.base58)", "From: \(fromMint.base58)", "To: \(toMint.base58)", "Amount: \(amount.formatted())")

        // Validate that required metadata is present for transaction building
        switch direction {
        case .buy(let targetMint):
            guard targetMint.vmMetadata != nil else {
                trace(.failure, components: "Target mint \(targetMint.symbol) missing VM metadata")
                completion(.failure(.invalidSwap))
                return
            }
            guard targetMint.launchpadMetadata != nil else {
                trace(.failure, components: "Target mint \(targetMint.symbol) missing launchpad metadata")
                completion(.failure(.invalidSwap))
                return
            }
        case .sell(let sourceMint):
            guard sourceMint.vmMetadata != nil else {
                trace(.failure, components: "Source mint \(sourceMint.symbol) missing VM metadata")
                completion(.failure(.invalidSwap))
                return
            }
            guard sourceMint.launchpadMetadata != nil else {
                trace(.failure, components: "Source mint \(sourceMint.symbol) missing launchpad metadata")
                completion(.failure(.invalidSwap))
                return
            }
        }

        // Also validate that USDF (core mint) has VM metadata
        guard MintMetadata.usdf.vmMetadata != nil else {
            trace(.failure, components: "USDF missing VM metadata")
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

        // Generate swap authority keypair for transaction signing
        let swapAuthority = KeyPair.generate()!

        // Store server parameters when received
        var receivedServerParameters: VerifiedSwapMetadata.ServerParameters?
        var verifiedMetadataSignature: Signature?

        reference.stream = service.statefulSwap { result in
            switch result.response {

                // 2. Upon successful submission of the Start message, server will
                // respond with parameters (nonce + blockhash) that we need to sign
            case .serverParameters(let parameters):
                guard case .currencyCreator(let serverParams) = parameters.kind else {
                    trace(.failure, components: "Unexpected server parameter kind")
                    _ = reference.stream?.sendEnd()
                    completion(.failure(.unknown))
                    return
                }

                guard let serverParameters = VerifiedSwapMetadata.ServerParameters(serverParams) else {
                    trace(.failure, components: "Failed to parse server parameters")
                    _ = reference.stream?.sendEnd()
                    completion(.failure(.unknown))
                    return
                }

                guard let responseParams = SwapResponseServerParameters(parameters) else {
                    trace(.failure, components: "Failed to parse response parameters")
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

                trace(.receive, components: "Received server parameters. Submitting \(signatures.count) signatures...", "Nonce: \(serverParameters.nonce.base58)", "Blockhash: \(serverParameters.blockhash.base58)")
                
                // 3. If submitted signature is valid, we'll receive a success
                // and the swap state will be created on the server
            case .success:
                guard let serverParams = receivedServerParameters,
                      let signature = verifiedMetadataSignature else {
                    trace(.failure, components: "Missing server parameters or signature")
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
                
                trace(.success, components: "Swap started successfully", "Swap ID: \(swapId.publicKey.base58)")
                _ = reference.stream?.sendEnd()
                completion(.success(metadata))
                
                // 3. If the submitted signature is invalid or other error occurs
            case .error(let error):
                var container: [String] = []
                container.append("Code: \(error.code)")
                
                let errors = error.errorDetails.flatMap { details in
                    switch details.type {
                    case .reasonString(let reason):
                        return ["Reason: \(reason.reason)"]
                        
                    case .invalidSignature(let signatureDetails):
                        return [
                            "Action index: \(signatureDetails.actionID)",
                            "Invalid signature: \((try? Signature(signatureDetails.providedSignature.value).base58) ?? "nil")",
                            "Transaction bytes: \(signatureDetails.expectedTransaction.value.hexEncodedString())",
                        ]
                    default:
                        return []
                    }
                }
                container.append(contentsOf: errors)
                
                trace(.failure, components: container)
                
                _ = reference.stream?.sendEnd()
                let intentError = ErrorSwap(error: error)
                completion(.failure(intentError))
                
            case .none:
                trace(.failure, components: "No response from server")
                _ = reference.stream?.sendEnd()
                completion(.failure(.unknown))
            }
        }
        
        reference.stream?.status.whenCompleteBlocking(onto: queue) { result in
            switch result {
            case .success(let status):
                if status.code == .ok {
                    trace(.success, components: "Stream closed")
                    // Completion called in the success block
                } else {
                    trace(.warning, components: "Stream closed: \(status)")
                    completion(.failure(.grpcStatus(status)))
                }
                
            case .failure(let error):
                trace(.failure, components: "GRPC Error - stream closed: \(error)")
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
                $0.currencyCreator = .with {
                    $0.clientParameters = clientProto
                }
            }
            let serialized = try verifiedMetadataProto.serializedData()
            let proof = owner.sign(serialized)

            let startRequest = Ocp_Transaction_V1_StatefulSwapRequest.with {
                $0.initiate = .with {
                    $0.kind = .currencyCreator(clientProto)
                    $0.owner = owner.publicKey.solanaAccountID
                    $0.swapAuthority = swapAuthority.publicKey.solanaAccountID
                    $0.proofSignature = proof.proto
                    $0.signature = $0.sign(with: owner)
                }
            }

            do {
                let bytes = try startRequest.serializedData()
                trace(.send, components: "StartSwap initiate proto (hex): \(bytes.hexEncodedString())")
            } catch {
                trace(.warning, components: "Failed to serialize StartSwap initiate proto for logging: \(error)")
            }

            _ = reference.stream?.sendMessage(startRequest)
        } catch {
            trace(.failure, components: "Failed to serialize client parameters for proof signature: \(error)")
            _ = reference.stream?.sendEnd()
            completion(.failure(.unknown))
            return
        }
    }
}

// MARK: - Types -

public enum SwapResult: Sendable {
    case finalized
    case submitted
}

public enum ErrorSwap: Error, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public enum DeniedReason: Int, Sendable {
        case unknown = -1
    }
    case denied([DeniedReason])
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
            let reasons: [DeniedReason] = error.errorDetails.compactMap {
                if case .denied(let details) = $0.type {
                    return DeniedReason(rawValue: details.code.rawValue)
                } else {
                    return nil
                }
            }
            
            self = .denied(reasons)
            
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
        case .denied(let reasons):
            let string = reasons.map { "\($0)" }.joined(separator: ", ")
            return "denied(\(string))"
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
