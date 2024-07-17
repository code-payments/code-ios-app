//
//  SendTransaction.swift
//  Code
//
//  Created by Dima Bart on 2021-02-17.
//

import Foundation
import CodeServices
import Combine
import CodeUI

@MainActor
class SendTransaction {
    
    let amount: KinAmount
    let organizer: Organizer
    let payload: Code.Payload
    let payloadData: Data
    
    private(set) var isInactive: Bool = false
    
    private let client: Client
    private let flowController: FlowController
    
    private var receivingAccount: PublicKey?
    
    private var messageStream: AnyCancellable? = nil
    
    // MARK: - Init -
    
    init(amount: KinAmount, organizer: Organizer, client: Client, flowController: FlowController) {
        self.amount = amount
        self.organizer = organizer
        self.payload = Code.Payload(
            kind: .cash,
            kin: amount.kin,
            nonce: .nonce
        )
        
        self.payloadData = payload.codeData()
        self.client = client
        self.flowController = flowController
    }
    
    deinit {
        trace(.note, components: "Deallocated SendTransaction for \(payload.rendezvous.publicKey.base58)")
        messageStream?.cancel()
        messageStream = nil
    }
    
    // MARK: - Start -
    
    func markInactive() {
        isInactive = true
        messageStream?.cancel()
        messageStream = nil
    }
    
    func startTransaction(completion: @escaping (Result<Void, Error>) -> Void) {
        trace(.send, components: "Rendezvous: \(payload.rendezvous.publicKey.base58)")
        
        let rendezvous = payload.rendezvous
        let amount = amount
        let tray = organizer.tray

        messageStream = client.openMessageStream(rendezvous: rendezvous) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let paymentRequest):
                
                // 1. Validate that destination hasn't been tampered with by
                // verifying the signature matches one that has been signed
                // with the rendezvous key.
                
                let isValid = self.client.verifyRequestToGrabBill(
                    destination: paymentRequest.account,
                    rendezvous: rendezvous.publicKey,
                    signature: paymentRequest.signature
                )
                
                guard isValid else {
                    let error = TransactionError.destinationSignatureInvalid
                    ErrorReporting.capturePayment(
                        error: error,
                        rendezvous: rendezvous.publicKey,
                        tray: tray,
                        amount: amount,
                        reason: "Request signature verification failed"
                    )
                    completion(.failure(error))
                    return
                }
                
                // 2. Send the funds to destination
                
                Task {
                    do {
                        try await self.sendFundsAndPoll(destinationTokenAccount: paymentRequest.account)
                        Analytics.transfer(
                            amount: amount,
                            successful: true,
                            error: nil
                        )
                        completion(.success(()))
                        
                    } catch {
                        Analytics.transfer(
                            amount: amount,
                            successful: false,
                            error: error
                        )
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                ErrorReporting.capturePayment(
                    error: error,
                    rendezvous: rendezvous.publicKey,
                    tray: tray,
                    amount: amount
                )
                completion(.failure(error))
            }
        }
    }
    
    private func sendFundsAndPoll(destinationTokenAccount destination: PublicKey) async throws {
        guard receivingAccount != destination else {
            // Ensure that we're processing one, and only one
            // transaction for each instance of SendTransaction.
            // Completion will be called by the first invocation
            // of this function.
            throw TransactionError.duplicateTransfer
        }
        
        receivingAccount = destination
        invalidateMessageStream()
        
        do {
            try await flowController.transfer(
                amount: amount,
                fee: 0,
                additionalFees: [],
                rendezvous: payload.rendezvous.publicKey,
                destination: destination
            )
            
            _ = try await client.pollIntentMetadata(
                owner: organizer.ownerKeyPair,
                intentID: payload.rendezvous.publicKey
            )
            
        } catch {
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: payload.rendezvous.publicKey,
                tray: organizer.tray,
                amount: amount,
                reason: "Failed to send funds on scan"
            )
            throw error
        }
    }
    
    private func invalidateMessageStream() {
        trace(.warning, components: "Close message stream")
        messageStream?.cancel()
        messageStream = nil
    }
}

extension SendTransaction {
    enum TransactionError: Swift.Error {
        case duplicateTransfer
        case destinationSignatureInvalid
    }
}
