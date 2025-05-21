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
    
    let payload: CashCode.Payload
    
    var ignoresStream = false
    
    private let client: Client
    private let owner: AccountCluster
    private let exchangedFiat: ExchangedFiat
    
    private var messageStream: AnyCancellable? = nil
    
    // MARK: - Init -
    
    init(client: Client, owner: AccountCluster, exchangedFiat: ExchangedFiat) {
        self.client       = client
        self.owner        = owner
        self.exchangedFiat = exchangedFiat
        self.payload      = .init(
            kind: .cash,
            fiat: exchangedFiat.converted,
            nonce: .nonce
        )
    }
    
    deinit {
        trace(.note, components: "Deallocated SendCashOperation for \(payload.rendezvous.publicKey.base58)")
        messageStream?.cancel()
        messageStream = nil
    }
    
    func start(completion: @escaping (Result<Void, Swift.Error>) -> Void) {
        let rendezvous = payload.rendezvous
        let exchangedFiat = exchangedFiat
        let owner = owner
        
        messageStream = self.client.openMessageStream(rendezvous: self.payload.rendezvous) { [weak self] result in
            guard let self = self else { return }
            
            guard !self.ignoresStream else {
                return
            }
            
            switch result {
            case .success(let paymentMetadata):
                
                // 1. Validate that destination hasn't been tampered with by
                // verifying the signature matches one that has been signed
                // with the rendezvous key.
                
                let isValid = client.verifyRequestToGrabBill(
                    destination: paymentMetadata.account,
                    rendezvous: rendezvous.publicKey,
                    signature: paymentMetadata.signature
                )
                
                guard isValid else {
                    let error: Error = Error.invalidPaymentDestinationSignature
                    completion(.failure(error))
                    return
                }
                
                // 2. Send the funds to destination
                
                Task {
                    do {
                        try await self.client.transfer(
                            exchangedFiat: exchangedFiat,
                            owner: owner,
                            destination: paymentMetadata.account,
                            rendezvous: rendezvous.publicKey,
                            isWithdrawal: false
                        )
                        
                        _ = try await self.client.pollIntentMetadata(
                            owner: owner.authority.keyPair,
                            intentID: rendezvous.publicKey
                        )
                        
                        completion(.success(()))
                        
                    } catch {
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func invalidateMessageStream() {
        trace(.warning, components: "Closed message stream")
        messageStream?.cancel()
        messageStream = nil
    }
}

extension SendCashOperation {
    enum Error: Swift.Error {
        case invalidPaymentDestinationSignature
    }
}
