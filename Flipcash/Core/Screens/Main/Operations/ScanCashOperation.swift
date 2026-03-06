//
//  ScanCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore
import Combine

@MainActor
class ScanCashOperation {
    
    private let client: Client
    private let flipClient: FlipClient
    private let database: Database
    private let owner: AccountCluster
    private let payload: CashCode.Payload
    
    private var messageStream: AnyCancellable? = nil
    
    // MARK: - Init -
    
    init(client: Client, flipClient: FlipClient, database: Database, owner: AccountCluster, payload: CashCode.Payload) {
        self.client     = client
        self.flipClient = flipClient
        self.database   = database
        self.owner      = owner
        self.payload    = payload
        trace(.open, components: "ScanCashOperation \(payload.rendezvous.publicKey.base58)")
    }

    deinit {
        trace(.close, components: "ScanCashOperation \(payload.rendezvous.publicKey.base58)")
        messageStream?.cancel()
        messageStream = nil
    }
    
    func start() async throws -> PaymentMetadata {
        let rendezvous = payload.rendezvous
        let owner = owner

        let (mint, verifiedState) = try await listenForMint(
            rendezvous: rendezvous
        )

        let vmAuthority = try await pullMintIfNeeded(for: mint)
        // 37WNqbyxSCDgYUyLYmbWsDMYzquKZbdC1U6HkRmFdjKH
        let mintCurrencyCluster = AccountCluster(
            authority: owner.authority,
            mint: mint,
            timeAuthority: vmAuthority
        )
        
        // We need to ensure the accounts for this mint
        // are created. This call is a no-op is the
        // account already exists
        try await client.createAccounts(
            owner: owner.authority.keyPair,
            mint: mint,
            cluster: mintCurrencyCluster,
            kind: .primary,
            derivationIndex: 0
        )
        
        return try await completePayment(
            destination: mintCurrencyCluster.vaultPublicKey,
            rendezvous: rendezvous,
            verifiedState: verifiedState
        )
    }
    
    private func pullMintIfNeeded(for mint: PublicKey) async throws -> PublicKey {
        if let vmAuthority = try database.getVMAuthority(mint: mint) {
            return vmAuthority
        } else {
            let mints = try await client.fetchMints(mints: [mint])
            guard let mintMetadata = mints[mint] else {
                throw Error.failedToFetchMint
            }
            
            try database.insert(mints: [mintMetadata], date: .now)
            
            guard let authority = mintMetadata.vmMetadata?.authority else {
                throw Error.failedToFetchMint
            }
            
            return authority
        }
    }
    
    private func listenForMint(rendezvous: KeyPair) async throws -> (PublicKey, VerifiedState?) {
        let maxAttempts = 10

        for i in 0..<maxAttempts {
            if i > 0 {
                try await Task.delay(milliseconds: 300)
            }

            do {
                let messages = try await client.fetchMessages(rendezvous: rendezvous)
                let result = messages.compactMap { message -> (PublicKey, VerifiedState?)? in
                    if case .requestToGiveBill(let mint, _) = message.kind {
                        return (mint, message.giveVerifiedState)
                    }
                    return nil
                }.first

                if let result {
                    return result
                }
            } catch {
                trace(.warning, components: "Failed to fetch messages (attempt \(i + 1)/\(maxAttempts)): \(error)")
                throw Error.connectionFailed
            }
        }

        throw Error.mintMessageNotFound
    }
    
    private func completePayment(destination: PublicKey, rendezvous: KeyPair, verifiedState: VerifiedState?) async throws -> PaymentMetadata {
        do {
            let isStreamOpen = try await client.sendRequestToGrabBill(
                destination: destination,
                rendezvous: rendezvous
            )

            guard isStreamOpen else {
                throw Error.noOpenStreamForRendezvous
            }

            let metadata = try await client.pollIntentMetadata(
                owner: owner.authority.keyPair,
                intentID: rendezvous.publicKey
            )

            if case .sendPayment(let paymentMetadata) = metadata {
                return PaymentMetadata(
                    exchangedFiat: paymentMetadata.exchangedFiat,
                    verifiedState: verifiedState
                )
            }

            if case .receivePayment(let paymentMetadata) = metadata {
                return PaymentMetadata(
                    exchangedFiat: paymentMetadata.exchangedFiat,
                    verifiedState: verifiedState
                )
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
        case failedToFetchMint
        case missingVMAuthority
        case mintMessageNotFound

        /// A network error prevented fetching messages from the
        /// rendezvous channel (e.g. no internet connection).
        case connectionFailed
    }
}
