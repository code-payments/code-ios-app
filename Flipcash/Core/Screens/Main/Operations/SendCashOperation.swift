//
//  SendCashOperation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashCore
import Combine

/// Orchestrates a peer-to-peer cash transfer through a rendezvous-based
/// handshake between sender and receiver.
///
/// ## Lifecycle
///
/// Calling ``start(completion:)`` kicks off two concurrent paths:
///
/// **Path 1 — Advertise (fire-and-forget Task)**
/// 1. Resolve the exchange-rate proof (`VerifiedState`), preferring the
///    value provided at init over the `RatesController` cache.
/// 2. Publish the bill on the rendezvous channel so the receiver knows
///    which mint and exchange data to expect.
///
/// **Path 2 — Listen (message stream)**
/// 1. Open a persistent gRPC stream on the rendezvous channel.
/// 2. When the receiver's grab request arrives, verify the destination
///    signature to prevent tampering.
/// 3. Transfer funds to the verified destination.
/// 4. Poll until on-chain settlement is confirmed.
///
/// Both paths share the resolved `VerifiedState` through
/// ``resolvedVerifiedState``. Path 2 reads this value when it's time to
/// transfer, falling back to the `RatesController` cache if Path 1 hasn't
/// written it yet. For brand-new currencies whose rate isn't cached, the
/// provided `verifiedState` at init is the only source of truth.
///
/// ## Completion Guarantee
///
/// The ``complete(with:completion:)`` method ensures the completion handler
/// fires exactly once. This guards against double-delivery from gRPC stream
/// reconnections (see `MessagingService.openMessageStream`) or overlapping
/// error paths (e.g. advertisement failure racing with a stream disconnect).
///
/// ## Not Recoverable
///
/// If ``sendRequestToGiveBill`` fails (network error, server down), the
/// operation terminates immediately. There is no retry — the receiver never
/// got the advertisement, so the stream will never deliver a grab request.
/// The bill is dismissed and the user sees an error.
///
/// ## Owned By
///
/// `Session` creates, stores (`sendOperation`), and tears down this
/// operation. The `ignoresStream` flag is toggled by Session when presenting
/// a share sheet to prevent stream events from dismissing the bill.
@MainActor
class SendCashOperation {

    let payload: CashCode.Payload

    /// When `true`, incoming stream messages are silently dropped. Session
    /// sets this while a share sheet is presented to prevent the bill from
    /// being dismissed underneath it.
    var ignoresStream = false

    private let client: Client
    private let database: Database
    private let ratesController: RatesController
    private let owner: AccountCluster
    private let exchangedFiat: ExchangedFiat

    /// The exchange-rate proof passed at init. Preferred over the
    /// `RatesController` cache because new currencies may not have a
    /// cached rate yet.
    private let providedVerifiedState: VerifiedState?

    private var messageStream: AnyCancellable? = nil

    /// Guards against processing more than one grab request per operation.
    private var hasProcessedPayment = false

    /// Guards against delivering the completion handler more than once.
    /// See ``complete(with:completion:)`` for details.
    private var hasCompleted = false

    /// The verified state resolved during Path 1 (advertisement). Path 2
    /// (transfer) reads this to avoid a redundant cache lookup. For new
    /// currencies this may be the only available source since the cache
    /// can be empty.
    private(set) var resolvedVerifiedState: VerifiedState?

    // MARK: - Init -

    init(client: Client, database: Database, ratesController: RatesController, owner: AccountCluster, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState? = nil) {
        self.client          = client
        self.database        = database
        self.ratesController = ratesController
        self.owner           = owner
        self.exchangedFiat   = exchangedFiat
        self.providedVerifiedState = verifiedState
        self.payload      = .init(
            kind: .cashMulticurrency,
            fiat: exchangedFiat.converted,
            nonce: .nonce
        )
        trace(.open, components: "SendCashOperation \(payload.rendezvous.publicKey.base58)")
    }

    deinit {
        trace(.close, components: "SendCashOperation \(payload.rendezvous.publicKey.base58)")
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
        
        // Send a message to the receiver with the mint and exchange
        // data so they can create the correct incoming accounts
        // on their end
        Task {
            do {
                let verifiedState: VerifiedState?
                if let provided = self.providedVerifiedState {
                    verifiedState = provided
                } else {
                    verifiedState = await self.ratesController.getVerifiedState(
                        for: exchangedFiat.converted.currencyCode,
                        mint: exchangedFiat.mint
                    )
                }

                self.resolvedVerifiedState = verifiedState

                _ = try await client.sendRequestToGiveBill(
                    mint: exchangedFiat.mint,
                    exchangedFiat: exchangedFiat,
                    verifiedState: verifiedState,
                    rendezvous: rendezvous
                )
            } catch {
                self.complete(with: .failure(error), completion: completion)
            }
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
                    self.complete(with: .failure(Error.invalidPaymentDestinationSignature), completion: completion)
                    return
                }

                // Mark payment as processed to prevent duplicate submissions
                self.hasProcessedPayment = true

                // 2. Send the funds to destination
                Task {
                    do {
                        // Use the verified state already resolved when the bill
                        // was created, falling back to the cache only if needed.
                        // New currencies may not be in the cache yet.
                        let verifiedState: VerifiedState
                        if let resolved = self.resolvedVerifiedState {
                            verifiedState = resolved
                        } else if let cached = await self.ratesController.getVerifiedState(
                            for: exchangedFiat.converted.currencyCode,
                            mint: exchangedFiat.mint
                        ) {
                            verifiedState = cached
                        } else {
                            throw Error.missingVerifiedState
                        }

                        try await self.client.transfer(
                            exchangedFiat: exchangedFiat,
                            verifiedState: verifiedState,
                            owner: owner,
                            destination: paymentMetadata.account,
                            rendezvous: rendezvous.publicKey
                        )

                        _ = try await self.client.pollIntentMetadata(
                            owner: owner.authority.keyPair,
                            intentID: rendezvous.publicKey
                        )

                        self.complete(with: .success(()), completion: completion)

                    } catch {
                        self.complete(with: .failure(error), completion: completion)
                    }
                }

            case .failure(let error):
                self.complete(with: .failure(error), completion: completion)
            }
        }
    }
    
    /// Delivers a result to the caller exactly once. Subsequent calls are
    /// no-ops, preventing double-completion from stream reconnections or
    /// overlapping error paths.
    private func complete(with result: Result<Void, Swift.Error>, completion: @escaping (Result<Void, Swift.Error>) -> Void) {
        guard !hasCompleted else { return }
        hasCompleted = true
        invalidateMessageStream()
        completion(result)
    }

    private func invalidateMessageStream() {
        trace(.warning, components: "Closed message stream")
        messageStream?.cancel()
        messageStream = nil
    }
}

extension SendCashOperation {
    enum Error: Swift.Error {
        /// The grab request's destination signature did not match the
        /// rendezvous key, indicating a potential man-in-the-middle attack.
        case invalidPaymentDestinationSignature

        /// The outgoing mint doesn't match the owner's timelock mint, and
        /// no VM authority was found in the database for the target mint.
        case missingMintMetadata

        /// No exchange-rate proof was available from either the provided
        /// value at init or the `RatesController` cache. Common for
        /// brand-new currencies that haven't been rate-cached yet.
        case missingVerifiedState
    }
}
