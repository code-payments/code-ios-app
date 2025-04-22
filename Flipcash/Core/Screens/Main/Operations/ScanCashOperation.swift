//
//  ScanCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore

@MainActor
class ScanCashOperation {
    
    private let client: Client
    private let owner: AccountCluster
    private let payload: CashCode.Payload
    
    // MARK: - Init -
    
    init(client: Client, owner: AccountCluster, payload: CashCode.Payload) {
        self.client  = client
        self.owner   = owner
        self.payload = payload
    }
    
    func start() async throws -> PaymentMetadata {
        do {
            let isStreamOpen = try await client.sendRequestToGrabBill(
                destination: owner.vaultPublicKey,
                rendezvous: payload.rendezvous
            )
            
            guard isStreamOpen else {
                throw Error.noOpenStreamForRendezvous
            }
            
            let metadata = try await client.pollIntentMetadata(
                owner: owner.authority.keyPair,
                intentID: payload.rendezvous.publicKey
            )
            
            if case .sendPayment(let paymentMetadata) = metadata {
                return paymentMetadata
            }
            
            throw Error.sendPaymentMetadataNotFound
            
        } catch Error.noOpenStreamForRendezvous {
            throw Error.noOpenStreamForRendezvous // Avoid capture
            
        } catch ClientError.pollLimitReached {
            throw ClientError.pollLimitReached // Avoid capture
            
        } catch {
//            ErrorReporting.captureError(error)
            throw error
        }
    }
}

extension ScanCashOperation {
    enum Error: Swift.Error {
        case noOpenStreamForRendezvous
        case sendPaymentMetadataNotFound
    }
}
