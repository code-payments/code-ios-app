//
//  ReceiveTransaction.swift
//  Code
//
//  Created by Dima Bart on 2021-02-17.
//

import Foundation
import CodeServices
import Combine

@MainActor
class ReceiveTransaction {
    
    let payload: Code.Payload
    
    private let organizer: Organizer
    private let client: Client
    private let stopwatch: Stopwatch
    
    // MARK: - Init -
    
    init(organizer: Organizer, payload: Code.Payload, client: Client) {
        self.organizer = organizer
        self.payload   = payload
        self.client    = client
        self.stopwatch = Stopwatch()
    }
    
    deinit {
        trace(.note, components: "Deallocated ReceiveTransaction for \(payload.rendezvous.publicKey.base58)")
    }
    
    // MARK: - Start -
    
    func start() async throws -> (metadata: PaymentMetadata, millisecondsToScan: Stopwatch.Milliseconds) {
        trace(.warning, components: "Payload Kind: \(payload.kind)")
        
        do {
            let isStreamOpen = try await client.sendRequestToGrabBill(
                destination: organizer.incomingVault,
                rendezvous: payload.rendezvous
            )
            
            guard isStreamOpen else {
                throw Error.noOpenStreamForRendezvous
            }
            
            let metadata = try await client.pollIntentMetadata(
                owner: organizer.ownerKeyPair,
                intentID: payload.rendezvous.publicKey
            )
            
            let grabTime = stopwatch.measure(in: .milliseconds)
            
            if case .sendPrivatePayment(let paymentMetadata) = metadata {
                return (paymentMetadata, grabTime)
            }
            
            if case .receivePaymentsPublicly(let paymentMetadata) = metadata {
                return (paymentMetadata, grabTime)
            }
            
            throw Error.sendPaymentMetadataNotFound
            
        } catch Error.noOpenStreamForRendezvous {
            throw Error.noOpenStreamForRendezvous // Avoid capture
            
        } catch ClientError.pollLimitReached {
            throw ClientError.pollLimitReached // Avoid capture
            
        } catch {
            ErrorReporting.captureError(error)
            throw error
        }
    }
}

extension ReceiveTransaction {
    enum Error: Swift.Error {
        case noOpenStreamForRendezvous
        case sendPaymentMetadataNotFound
    }
}
