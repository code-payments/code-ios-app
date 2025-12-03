//
//  SwapService.swift
//  FlipchatServices
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
final class SwapService: CodeService<Code_Transaction_V2_TransactionNIOClient>, @unchecked Sendable {
    
    typealias BidirectionalStartSwapStream = BidirectionalStreamReference<Code_Transaction_V2_StartSwapRequest, Code_Transaction_V2_StartSwapResponse>
    typealias BidirectionalSwapStream = BidirectionalStreamReference<Code_Transaction_V2_SwapRequest, Code_Transaction_V2_SwapResponse>
    
    // MARK: - StartSwap -
    
    /// StartSwap initiates the swap process by coordinating verified metadata with the server.
    /// This establishes the swap state and reserves blockchain resources (nonce + blockhash).
    func startSwap(
        swapId: SwapId,
        fromMint: PublicKey,
        toMint: PublicKey,
        amount: Quarks,
        fundingID: PublicKey,
        owner: KeyPair,
        completion: @escaping (Result<SwapMetadata, ErrorSwap>) -> Void
    ) {
        trace(.send, components: "Swap ID: \(swapId.publicKey.base58)", "From: \(fromMint.base58)", "To: \(toMint.base58)", "Amount: \(amount.formatted())")
        
        let reference = BidirectionalStartSwapStream()
        let queue = self.queue // Capture queue, not self
        
        // Store client parameters for verification metadata construction
        let clientParameters = VerifiedSwapMetadata.ClientParameters(
            id: swapId,
            fromMint: fromMint,
            toMint: toMint,
            amount: amount,
            fundingSource: .submitIntent,
            fundingID: fundingID
        )
        
        // Intentionally creates a retain-cycle using closures to ensure that we have
        // a strong reference to the stream at all times. Doing so ensures that the
        // callers don't have to manage the pointer to this stream and keep it alive
        reference.retain()
        
        // Store server parameters when received
        var receivedServerParameters: VerifiedSwapMetadata.ServerParameters?
        var verifiedMetadataSignature: Signature?
        
        reference.stream = service.startSwap { result in
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
                
                // Store for later use in success response
                receivedServerParameters = serverParameters
                
                // Construct verified metadata for signing
                let verifiedMetadata = VerifiedSwapMetadata(
                    clientParameters: clientParameters,
                    serverParameters: serverParameters
                )
                
                do {
                    // Sign the verified metadata to prevent tampering
                    let data = try verifiedMetadata.proto.serializedData()
                    let signature = owner.sign(data)
                    verifiedMetadataSignature = signature
                    
                    // Send signature back to server
                    let submitSignature = Code_Transaction_V2_StartSwapRequest.with {
                        $0.submitSignature = .with {
                            $0.signature = signature.proto
                        }
                    }
                    
                    _ = reference.stream?.sendMessage(submitSignature)
                    
                    trace(.receive, components: "Received server parameters. Submitting signature...", "Nonce: \(serverParameters.nonce.base58)", "Blockhash: \(serverParameters.blockhash.base58)")
                    
                } catch {
                    trace(.failure, components: "Failed to serialize verified metadata: \(error)")
                    _ = reference.stream?.sendEnd()
                    completion(.failure(.unknown))
                }
                
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
                
            default:
                trace(.failure, components: "Unexpected response type")
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
        let startRequest = Code_Transaction_V2_StartSwapRequest.with {
            $0.start = .with {
                $0.currencyCreator = clientParameters.proto
                $0.owner = owner.publicKey.solanaAccountID
                $0.signature = $0.sign(with: owner)
            }
        }
        _ = reference.stream?.sendMessage(startRequest)
    }
    
    // MARK: - GetSwap -
    
    /// GetSwap fetches the current state and metadata for a specific swap
    func getSwap(
        swapId: SwapId,
        owner: KeyPair
    ) async throws -> SwapMetadata {
        trace(.send, components: "Swap ID: \(swapId.publicKey.base58)")
        
        let request = Code_Transaction_V2_GetSwapRequest.with {
            $0.id = swapId.codeSwapID
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let call = service.getSwap(request)
            call.response.whenComplete { result in
                switch result {
                case .success(let response):
                    let error = ErrorGetSwap(rawValue: response.result.rawValue) ?? .unknown
                    guard error == .ok else {
                        trace(.failure, components: "Error: \(error)", "Swap ID: \(swapId.publicKey.base58)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let metadata = SwapMetadata(response.swap) else {
                        trace(.failure, components: "Failed to parse swap metadata", "Swap ID: \(swapId.publicKey.base58)")
                        continuation.resume(throwing: ErrorGetSwap.failedToParse)
                        return
                    }
                    
                    trace(.success, components: "Swap ID: \(swapId.publicKey.base58)", "State: \(metadata.state)")
                    continuation.resume(returning: metadata)
                    
                case .failure(let error):
                    trace(.failure, components: "gRPC error: \(error)", "Swap ID: \(swapId.publicKey.base58)")
                    continuation.resume(throwing: ErrorGetSwap.unknown)
                }
            }
        }
    }
    
    // MARK: - Poll & Execute -
    
    /// Polls GetSwap until the swap reaches FUNDED state, then executes it
    func executeSwap(
        swapId: SwapId,
        owner: KeyPair,
        swapAuthority: KeyPair,
        maxAttempts: Int,
        interval: TimeInterval
    ) async throws -> Result<SwapResult, ErrorSwap> {
        let metadata = try await pollSwapUntilFunded(
            swapId: swapId,
            owner: owner,
            maxAttempts: maxAttempts,
            interval: interval,
            attempt: 0
        )
        
        // Once funded, execute the swap
        return try await executeSwapInternal(
            swapId: swapId,
            owner: owner,
            swapAuthority: swapAuthority,
            waitForBlockchain: true
        )
    }
    
    /// Polls GetSwap until the swap reaches FUNDED state or times out
    private func pollSwapUntilFunded(
        swapId: SwapId,
        owner: KeyPair,
        maxAttempts: Int,
        interval: TimeInterval,
        attempt: Int
    ) async throws -> SwapMetadata {
        guard attempt < maxAttempts else {
            trace(.failure, components: "Polling timed out after \(maxAttempts) attempts", "Swap ID: \(swapId.publicKey.base58)")
            throw ErrorSwap.unknown
        }
        
        let metadata: SwapMetadata
        do {
            metadata = try await getSwap(swapId: swapId, owner: owner)
        } catch {
            trace(.failure, components: "Failed to get swap state: \(error)", "Swap ID: \(swapId.publicKey.base58)")
            throw ErrorSwap.unknown
        }
        
        switch metadata.state {
        case .funded:
            // Swap is ready to execute
            return metadata
            
        case .finalized:
            // Already finalized (server executed it)
            return metadata
            
        case .failed, .cancelled:
            // Swap failed or was cancelled
            trace(.failure, components: "Swap reached terminal state: \(metadata.state)", "Swap ID: \(swapId.publicKey.base58)")
            throw ErrorSwap.unknown
            
        case .created, .funding, .submitting, .cancelling:
            // Still in progress, poll again
            trace(.receive, components: "Swap state: \(metadata.state), polling again...", "Attempt \(attempt + 1)/\(maxAttempts)")
            
            try await Task.sleep(until: .now + .seconds(interval), tolerance: nil)
            return try await pollSwapUntilFunded(
                swapId: swapId,
                owner: owner,
                maxAttempts: maxAttempts,
                interval: interval,
                attempt: attempt + 1
            )
            
        case .unknown:
            trace(.failure, components: "Swap in unknown state", "Swap ID: \(swapId.publicKey.base58)")
            throw ErrorSwap.unknown
        }
    }
    
    // MARK: - Execute Swap -
    
    /// Executes a swap that's in FUNDED state
    private func executeSwapInternal(
        swapId: SwapId,
        owner: KeyPair,
        swapAuthority: KeyPair,
        waitForBlockchain: Bool
    ) async throws -> Result<SwapResult, ErrorSwap> {
        trace(.send, components: "Executing swap", "Swap ID: \(swapId.publicKey.base58)")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let reference = BidirectionalSwapStream()
                let queue = self.queue // Capture queue, not self
                
                reference.retain()
                
                reference.stream = service.swap { result in
                    switch result.response {
                        
                        // Server provides parameters needed to build the swap transaction
                    case .serverParameters(let parameters):
                        trace(.receive, components: "Received server parameters for swap execution")
                        
                        // TODO: Build swap transaction with server parameters
                        // For now, just acknowledge receipt
                        let error = ErrorSwap.unknown
                        trace(.failure, components: "Incomplete implementation - needs transaction building")
                        _ = reference.stream?.sendEnd()
                        continuation.resume(throwing: error)
                        
                        // Swap was submitted or finalized
                    case .success(let success):
                        let result: SwapResult
                        switch success.code {
                        case .swapSubmitted:
                            result = .submitted
                        case .swapFinalized:
                            result = .finalized
                        case .UNRECOGNIZED:
                            result = .submitted
                        }
                        
                        trace(.success, components: "Swap completed: \(result)", "Swap ID: \(swapId.publicKey.base58)")
                        _ = reference.stream?.sendEnd()
                        continuation.resume(returning: .success(result))
                        
                        // Error during swap execution
                    case .error(let error):
                        trace(.failure, components: "Swap execution error: \(error.code)")
                        _ = reference.stream?.sendEnd()
                        continuation.resume(returning: .failure(ErrorSwap.init(error: error)))
                        
                    case .none:
                        trace(.failure, components: "No response from server")
                        _ = reference.stream?.sendEnd()
                        continuation.resume(throwing: ErrorSwap.unknown)
                        
                    default:
                        trace(.failure, components: "Unexpected response type")
                        _ = reference.stream?.sendEnd()
                        continuation.resume(throwing: ErrorSwap.unknown)
                    }
                }
                
                reference.stream?.status.whenCompleteBlocking(onto: queue) { result in
                    switch result {
                    case .success(let status):
                        if status.code == .ok {
                            trace(.success, components: "Swap stream closed")
                        } else {
                            trace(.warning, components: "Swap stream closed: \(status)")
                            continuation.resume(throwing: ErrorSwap.grpcStatus(status))
                    
                        }
                        
                    case .failure(let error):
                        trace(.failure, components: "GRPC Error - swap stream closed: \(error)")
                        continuation.resume(throwing: ErrorSwap.grpcError(error))
                    }
                    
                    reference.release()
                }
                
                // Send initiate request
                let initiateRequest = Code_Transaction_V2_SwapRequest.with {
                    $0.initiate = .with {
                        $0.kind = .stateful(
                            Code_Transaction_V2_SwapRequest.Initiate.Stateful.with {
                                $0.swapID = swapId.codeSwapID
                                $0.owner = owner.publicKey.solanaAccountID
                                $0.swapAuthority = swapAuthority.publicKey.solanaAccountID
                            }
                        )
                    }
                }
                _ = reference.stream?.sendMessage(initiateRequest)
            }
        } onCancel: {
            trace(.failure, components: "swap cancelled")
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
    
    init(error: Code_Transaction_V2_StartSwapResponse.Error) {
        let reasonStrings: [String] = error.errorDetails.compactMap {
            if case .reasonString(let object) = $0.type {
                return !object.reason.isEmpty ? object.reason : nil
            } else {
                return nil
            }
        }
        
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
    
    init(error: Code_Transaction_V2_SwapResponse.Error) {
        let reasonStrings: [String] = error.errorDetails.compactMap {
            if case .reasonString(let object) = $0.type {
                return !object.reason.isEmpty ? object.reason : nil
            } else {
                return nil
            }
        }
        
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
        case .swapFailed:
            self = .failed
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
