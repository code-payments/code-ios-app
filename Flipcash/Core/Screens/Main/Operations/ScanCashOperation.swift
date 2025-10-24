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
    }
    
    deinit {
        trace(.note, components: "Deallocated SendCashOperation for \(payload.rendezvous.publicKey.base58)")
        messageStream?.cancel()
        messageStream = nil
    }
    
    func start() async throws -> PaymentMetadata {
        let rendezvous = payload.rendezvous
        let owner = owner
        
        let mint = try await listenForMint(
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
            rendezvous: rendezvous
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
    
    private func listenForMint(rendezvous: KeyPair) async throws -> PublicKey {
        let messages = try await client.fetchMessages(rendezvous: rendezvous)
        let mint = messages.compactMap { message in
            if case .requestToGiveBill(let mint) = message.kind {
                return mint
            }
            return nil
        }.first
        
        guard let mint else {
            throw ErrorGeneric.unknown
        }
        
        return mint
    }
    
    private func completePayment(destination: PublicKey, rendezvous: KeyPair) async throws -> PaymentMetadata {
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
                return paymentMetadata
            }
            
            if case .receivePayment(let paymentMetadata) = metadata {
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
        case failedToFetchMint
        case missingVMAuthority
    }
}
