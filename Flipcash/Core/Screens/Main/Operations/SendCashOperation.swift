//
//  SendCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore
import Combine

@MainActor
class SendCashOperation {
    
    private let client: Client
    private let owner: AccountCluster
    private let exchangeFiat: ExchangedFiat
    private let payload: CashCode.Payload
    
    private var messageStream: AnyCancellable? = nil
    
    // MARK: - Init -
    
    init(client: Client, owner: AccountCluster, exchangeFiat: ExchangedFiat) {
        self.client       = client
        self.owner        = owner
        self.exchangeFiat = exchangeFiat
        self.payload      = .init(
            kind: .cash,
            fiat: exchangeFiat.usdc,
            nonce: .nonce
        )
    }
    
    deinit {
        trace(.note, components: "Deallocated SendCashOperation for \(payload.rendezvous.publicKey.base58)")
        messageStream?.cancel()
        messageStream = nil
    }
    
    func start() async throws {
        let rendezvous = payload.rendezvous
        let paymentMetadata = try await waitForPaymentMetadata()
        
        // 1. Validate that destination hasn't been tampered with by
        // verifying the signature matches one that has been signed
        // with the rendezvous key.
        
        let isValid = client.verifyRequestToGrabBill(
            destination: paymentMetadata.account,
            rendezvous: rendezvous.publicKey,
            signature: paymentMetadata.signature
        )
        
        guard isValid else {
            let error = Error.invalidPaymentDestinationSignature
//            ErrorReporting.capturePayment(
//                error: error,
//                rendezvous: rendezvous.publicKey,
//                tray: tray,
//                amount: amount,
//                reason: "Request signature verification failed"
//            )
            throw error
        }
        
        // 2. Send the funds to destination
        
        do {
            try await client.transfer(
                exchangedFiat: exchangeFiat,
                owner: owner,
                destination: paymentMetadata.account
            )
            
            _ = try await client.pollIntentMetadata(
                owner: owner.authority.keyPair,
                intentID: rendezvous.publicKey
            )
            
        } catch {
//            ErrorReporting.capture(error)
            throw error
        }
    }
    
    private func waitForPaymentMetadata() async throws -> PaymentRequest {
        try await withCheckedThrowingContinuation { c in
            messageStream = client.openMessageStream(rendezvous: payload.rendezvous) { [weak self] in
                if self?.messageStream != nil {
                    c.resume(with: $0)
                    self?.messageStream?.cancel()
                    self?.messageStream = nil
                }
            }
        }
    }
}

extension SendCashOperation {
    enum Error: Swift.Error {
        case invalidPaymentDestinationSignature
    }
}
