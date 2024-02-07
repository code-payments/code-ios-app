//
//  TransactionService+Swap.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC
import NIO

extension TransactionService {
    
    typealias BidirectionalSwapStream = BidirectionalStreamReference<Code_Transaction_V2_SwapRequest, Code_Transaction_V2_SwapResponse>
    
    func initiateSwap(organizer: Organizer, completion: @escaping (Result<SwapIntent, Error>) -> Void) {
        let intent = SwapIntent(organizer: organizer)
        
        trace(.send, components: "Swap ID: \(intent.id.base58)")
        
        submit(intent: intent) { result in
            switch result {
            case .success(let intent):
                trace(.success)
                completion(.success(intent))
                
            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    private func submit(intent: SwapIntent, completion: @escaping (Result<SwapIntent, ErrorSubmitIntent>) -> Void) {
        
        let reference = BidirectionalSwapStream()
        
        // Intentionally creates a retain-cycle using closures to ensure that we have
        // a strong reference to the stream at all times. Doing so ensures that the
        // callers don't have to manage the pointer to this stream and keep it alive
        reference.retain()
        
        reference.stream = service.swap { result in
            switch result.response {
            
            // 2. Upon successful submission of intent action the server will
            // respond with parameters that we'll need to apply to the intent
            // before crafting and signing the transactions.
            case .serverParamenters(let parameters):
                do {
                    let configParameters = try SwapConfigParameters(parameters)
                    
                    intent.parameters = configParameters
                    
                    let submitSignatures = try intent.requestToSubmitSignatures()
                    _ = reference.stream?.sendMessage(submitSignatures)
                    
                    trace(.receive, components: "Intent: \(intent.id.base58)")
                    
                } catch {
                    trace(.failure, components: "Received parameters but failed to apply them: \(error)", "Intent: \(intent.id.base58)")
                    completion(.failure(.unknown))
                }
                
            // 3. If submitted transaction signatures are valid and match
            // the server, we'll receive a success for the submitted intent.
            case .success(let success):
                trace(.success, components: "Success: \(success.code.rawValue)", "Intent: \(intent.id.base58)")
                _ = reference.stream?.sendEnd()
                completion(.success(intent))
                
            // 3. If the submitted transaction signatures don't match, the
            // intent is considered failed. Something must have gone wrong
            // on the transaction creation or signing on our side.
            case .error(let error):
                var container: [String] = []
                
                container.append("Code: \(error.code)")
                
                let errors = error.errorDetails.flatMap { details in
                    switch details.type {
                    case .reasonString(let reason):
                        return [
                            "Reason: \(reason.reason)"
                        ]
                        
                    case .invalidSignature(let signatureDetails):
                        return [
                            "Action index: \(signatureDetails.actionID)",
                            "Invalid signature: \(Signature(signatureDetails.providedSignature.value)?.base58 ?? "nil")",
                            "Transaction bytes: \(signatureDetails.expectedTransaction.value.hexEncodedString())",
                            "Transaction expected: \(SolanaTransaction(data: signatureDetails.expectedTransaction.value)!)",
                            "iOS produced: \(intent.transaction(using: intent.parameters!))"
                        ]
                    default:
                        return []
                    }
                }
                
                container.append(contentsOf: errors)
                
                trace(.failure, components: container)
                
                _ = reference.stream?.sendEnd()
                let intentError = ErrorSubmitIntent(rawValue: error.code.rawValue) ?? .unknown
                completion(.failure(intentError))
                
            default:
                _ = reference.stream?.sendEnd()
                completion(.failure(.unknown))
            }
        }
        
        // TODO: Fix gRPC validation failures
        // If client's response fails gRPC validation, the request
        // will fail in the block below and the completion won't get
        // called. We should handle that case more gracefully and ensure
        // it's robust.
        
        reference.stream?.status.whenCompleteBlocking(onto: queue) { result in
            trace(.warning, components: "Stream closed: \(result)")
            
            // We release the stream reference after the stream has been
            // closed and there's no further actions required
            reference.release()
        }
        
        let initiateSwap = Code_Transaction_V2_SwapRequest.with {
            $0.initiate = .with {
                $0.owner = intent.owner.publicKey.codeAccountID
                $0.swapAuthority = intent.swapCluster.authorityPublicKey.codeAccountID
                $0.signature = $0.sign(with: intent.owner)
            }
        }
        
        _ = reference.stream?.sendMessage(initiateSwap)
    }
}
