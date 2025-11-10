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
    private let database: Database
    private let owner: AccountCluster
    private let exchangedFiat: ExchangedFiat

    private var messageStream: AnyCancellable? = nil
    private var hasProcessedPayment = false
    
    // MARK: - Init -
    
    init(client: Client, database: Database, owner: AccountCluster, exchangedFiat: ExchangedFiat) {
        self.client       = client
        self.database     = database
        self.owner        = owner
        self.exchangedFiat = exchangedFiat
        self.payload      = .init(
            kind: .cashMulticurrency,
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
        var owner = owner
        
        // Ensure that our outgoing (source) account mint
        // matches the mint of the funds being sent
        if owner.timelock.mint != exchangedFiat.mint {
            guard let vmAuthority = try? database.getVMAuthority(mint: exchangedFiat.mint) else {
                completion(.failure(Error.missingMintMetadata))
                return
            }
            
            owner = owner.use(
                mint: exchangedFiat.mint,
                timeAuthority: vmAuthority
            )
        }
        
        // Send a message to the receiver with the mint
        // so they can create the correct incoming accounts
        // on their end
        Task {
            try await client.sendRequestToGiveBill(
                mint: exchangedFiat.mint,
                rendezvous: rendezvous
            )
        }
        
        messageStream = self.client.openMessageStream(rendezvous: rendezvous) { [weak self] result in
            guard let self = self else { return }

            guard !self.ignoresStream else {
                return
            }

            // Prevent processing duplicate payment requests
            guard !self.hasProcessedPayment else {
                trace(.warning, components: "Ignoring duplicate payment request for rendezvous: \(rendezvous.publicKey.base58)")
                return
            }

            switch result {
            case .success(let messages):
                // Ignore non-payment metadata messages
                guard let paymentMetadata = messages.compactMap({ $0.paymentRequest }).first else {
                    return
                }

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

                // Mark payment as processed to prevent duplicate submissions
                self.hasProcessedPayment = true

                // Close the message stream to prevent further messages
                self.invalidateMessageStream()

                // 2. Send the funds to destination
                Task {
                    do {
                        try await self.client.transfer(
                            exchangedFiat: exchangedFiat,
                            owner: owner,
                            destination: paymentMetadata.account,
                            rendezvous: rendezvous.publicKey
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
        case missingMintMetadata
    }
}
