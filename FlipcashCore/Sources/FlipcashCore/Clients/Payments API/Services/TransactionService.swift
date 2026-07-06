//
//  TransactionService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore
import DeviceCheck

private let logger = Logger(label: "flipcash.transaction-service")

final class TransactionService: Sendable {
    typealias BidirectionalStream = BidirectionalGRPCStream<Ocp_Transaction_V1_SubmitIntentRequest, Ocp_Transaction_V1_SubmitIntentResponse>

    private let client: GRPCClient<AppTransport>
    private let service: Ocp_Transaction_V1_Transaction.Client<AppTransport>

    // Swap service for managing token swaps
    let swapService: SwapService

    init(client: GRPCClient<AppTransport>) {
        self.client = client
        self.service = Ocp_Transaction_V1_Transaction.Client(wrapping: client)
        self.swapService = SwapService(client: client)
    }

    // MARK: - Account Creation -

    func createAccounts(owner: KeyPair, mint: PublicKey, cluster: AccountCluster, kind: AccountKind, derivationIndex: Int, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Creating accounts")

        let intent = IntentCreateAccount(
            owner: owner.publicKey,
            mint: mint,
            cluster: cluster,
            kind: kind,
            derivationIndex: derivationIndex
        )

        submit(intent: intent, owner: owner) { result in
            switch result {
            case .success(_):
                logger.info("Accounts created successfully")
                completion(.success(()))

            case .failure(let error):
                logger.error("Failed to create accounts", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    // MARK: - Transfer -

    func transfer(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, sourceCluster: AccountCluster, destination: PublicKey, destinationOwner: PublicKey? = nil, appMetadata: Data? = nil, owner: KeyPair, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Sending transfer")

        let intent = IntentTransfer(
            rendezvous: rendezvous,
            sourceCluster: sourceCluster,
            destination: destination,
            destinationOwner: destinationOwner,
            exchangedFiat: exchangedFiat,
            verifiedState: verifiedState,
            appMetadata: appMetadata
        )

        submit(intent: intent, owner: owner) { result in
            switch result {
            case .success(_):
                logger.info("Transfer succeeded")
                completion(.success(()))

            case .failure(let error):
                logger.error("Transfer failed", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    func withdraw(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, fee: TokenAmount, sourceCluster: AccountCluster, destinationMetadata: DestinationMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Sending withdrawal")

        do {
            let intent = try IntentWithdraw(
                sourceCluster: sourceCluster,
                fee: fee,
                destinationMetadata: destinationMetadata,
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState
            )

            submit(intent: intent, owner: owner) { result in
                switch result {
                case .success(_):
                    logger.info("Withdrawal succeeded")
                    completion(.success(()))

                case .failure(let error):
                    logger.error("Withdrawal failed", metadata: ["error": "\(error)"])
                    completion(.failure(error))
                }
            }

        } catch {
            logger.error("Failed to build withdraw intent", metadata: ["error": "\(error)"])
            completion(.failure(error))
        }
    }

    func sendCashLink(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, ownerCluster: AccountCluster, giftCard: GiftCardCluster, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Sending cash link", metadata: [
            "giftCardVault": "\(giftCard.cluster.vaultPublicKey.base58)",
            "amount": "\(exchangedFiat.usdfValue.formatted(suffix: " USDF"))"
        ])

        let intent = IntentSendCashLink(
            rendezvous: rendezvous,
            sourceCluster: ownerCluster,
            giftCard: giftCard,
            exchangedFiat: exchangedFiat,
            verifiedState: verifiedState
        )

        submit(intent: intent, owner: ownerCluster.authority.keyPair) { result in
            switch result {
            case .success(_):
                logger.info("Cash link sent successfully")
                completion(.success(()))

            case .failure(let error):
                logger.error("Failed to send cash link", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    func receiveCashLink(usdf: TokenAmount, ownerCluster: AccountCluster, giftCard: GiftCardCluster, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Receiving cash link", metadata: [
            "giftCardVault": "\(giftCard.cluster.vaultPublicKey.base58)",
            "amount": "\(FiatAmount.usd(usdf.decimalValue).formatted(suffix: " USDF"))"
        ])

        let intent = IntentReceiveCashLink(
            ownerCluster: ownerCluster,
            giftCard: giftCard,
            usdf: usdf
        )

        submit(intent: intent, owner: ownerCluster.authority.keyPair) { result in
            switch result {
            case .success(_):
                logger.info("Cash link received successfully")
                completion(.success(()))

            case .failure(let error):
                logger.error("Failed to receive cash link", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    func voidCashLink(giftCardVault: PublicKey, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorVoidGiftCard>) -> Void) {
        logger.info("Voiding cash link", metadata: ["giftCard": "\(giftCardVault.base58)"])

        let request = Ocp_Transaction_V1_VoidGiftCardRequest.with {
            $0.giftCardVault = giftCardVault.solanaAccountID
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }

        Task {
            do {
                let response = try await service.voidGiftCard(request, options: .unaryDefault)
                let error = ErrorVoidGiftCard(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to void cash link", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("Cash link voided", metadata: ["giftCard": "\(giftCardVault.base58)"])
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(ErrorVoidGiftCard.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    // MARK: - Swaps -

    /// A buy is a swap from USDF to desired token (Phase 1 + Phase 2 via IntentFundSwap)
    func buy(amount: ExchangedFiat, verifiedState: VerifiedState, of token: MintMetadata, owner: AccountCluster, completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void) {
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey
        let ownerKeyPair = owner.authority.keyPair

        logger.info("Starting buy", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "symbol": "\(token.symbol)"
        ])

        // Phase 1: Create swap state on the server
        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: token),
            amount: amount.onChainAmount,
            fundingSource: .submitIntent(id: fundingIntentID),
            owner: ownerKeyPair
        ) { result in
            switch result {
            case .success(let metadata):
                logger.info("Swap state created", metadata: ["swapId": "\(swapId.publicKey.base58)"])

                // Phase 2: Fund via IntentFundSwap
                let fundingIntent = IntentFundSwap(
                    intentID: fundingIntentID,
                    swapId: metadata.swapId,
                    sourceCluster: owner,
                    amount: amount,
                    verifiedState: verifiedState,
                    fromMint: .usdf,
                    toMint: token
                )

                self.submit(intent: fundingIntent, owner: ownerKeyPair) { fundingResult in
                    switch fundingResult {
                    case .success:
                        logger.info("Buy swap completed", metadata: ["intentId": "\(fundingIntentID.base58)"])
                        completion(.success(swapId))
                    case .failure(let error):
                        logger.error("Failed to fund buy swap", metadata: ["error": "\(error)"])
                        completion(.failure(.fundingIntent(error)))
                    }
                }

            case .failure(let error):
                logger.error("Failed to start buy swap", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    /// Withdraws USDF to a Solana wallet as USDC via Coinbase Stable Swapper.
    /// Phase 1 + Phase 2 mirroring `buy()`: stateful swap stream → IntentFundSwap submission.
    func withdrawAsUSDC(
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        destinationOwner: PublicKey,
        fee: TokenAmount,
        sourceCluster: AccountCluster,
        completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void
    ) {
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey
        let ownerKeyPair = sourceCluster.authority.keyPair

        logger.info("Starting USDF withdrawal", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "destinationOwner": "\(destinationOwner.base58)",
            "fee": "\(fee.quarks)"
        ])

        // Phase 1: open the StatefulSwap stream with the stablecoin variant
        let netSwapQuarks = amount.onChainAmount.quarks > fee.quarks
            ? amount.onChainAmount.quarks - fee.quarks
            : 0
        let netSwapAmount = TokenAmount(quarks: netSwapQuarks, mint: amount.onChainAmount.mint)

        swapService.swap(
            swapId: swapId,
            direction: .withdraw(mint: .usdc),
            amount: netSwapAmount,
            feeAmount: fee,
            fundingSource: .submitIntent(id: fundingIntentID),
            owner: ownerKeyPair,
            kind: .stablecoin(destinationOwner: destinationOwner)
        ) { result in
            switch result {
            case .success(let metadata):
                logger.info("Swap state created", metadata: [
                    "swapId": "\(swapId.publicKey.base58)"
                ])

                // Phase 2: fund via IntentFundSwap (same pattern as buy())
                let fundingIntent = IntentFundSwap(
                    intentID: fundingIntentID,
                    swapId: metadata.swapId,
                    sourceCluster: sourceCluster,
                    amount: amount,
                    verifiedState: verifiedState,
                    fromMint: .usdf,
                    toMint: .usdc
                )

                self.submit(intent: fundingIntent, owner: ownerKeyPair) { fundingResult in
                    switch fundingResult {
                    case .success:
                        logger.info("USDF withdrawal completed", metadata: [
                            "intentId": "\(fundingIntentID.base58)"
                        ])
                        completion(.success(swapId))
                    case .failure(let error):
                        logger.error("Failed to fund USDF withdrawal", metadata: ["error": "\(error)"])
                        completion(.failure(.fundingIntent(error)))
                    }
                }

            case .failure(let error):
                logger.error("Failed to start USDF withdrawal", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    /// A buy funded by an external wallet (Phase 1 only — no IntentFundSwap).
    /// The transaction signature is provided; the caller submits it to
    /// the chain after the server confirms the swap state.
    func buyWithExternalFunding(
        swapId: SwapId,
        amount: ExchangedFiat,
        of token: MintMetadata,
        owner: KeyPair,
        transactionSignature: Signature,
        completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void
    ) {
        logger.info("Starting externally-funded buy", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "symbol": "\(token.symbol)",
            "swapId": "\(swapId.publicKey.base58)"
        ])

        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: token),
            amount: amount.onChainAmount,
            fundingSource: .externalWallet(transactionSignature: transactionSignature),
            owner: owner
        ) { result in
            switch result {
            case .success:
                logger.info("Buy swap initiated with external funding", metadata: ["swapId": "\(swapId.publicKey.base58)"])
                completion(.success(swapId))
            case .failure(let error):
                logger.error("Failed to start externally-funded buy swap", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    /// A buy of an existing currency funded by a Coinbase Onramp order.
    /// Server watches the order, holds the client-signed transaction, and
    /// submits it on-chain once Coinbase reports the funding as complete.
    /// Wire-identical to `buyWithExternalFunding` except the funding source
    /// is the order ID instead of an on-chain transaction signature.
    func buyWithCoinbaseOnramp(
        swapId: SwapId,
        amount: ExchangedFiat,
        of token: MintMetadata,
        owner: KeyPair,
        orderId: String,
        completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void
    ) {
        logger.info("Starting Coinbase-onramp-funded buy", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "symbol": "\(token.symbol)",
            "swapId": "\(swapId.publicKey.base58)",
            "orderId": "\(orderId)"
        ])

        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: token),
            amount: amount.onChainAmount,
            fundingSource: .coinbaseOnramp(orderId: orderId),
            owner: owner
        ) { result in
            switch result {
            case .success:
                logger.info("Buy swap initiated with Coinbase onramp funding", metadata: [
                    "swapId": "\(swapId.publicKey.base58)",
                    "orderId": "\(orderId)"
                ])
                completion(.success(swapId))
            case .failure(let error):
                logger.error("Failed to start Coinbase-onramp-funded buy swap", metadata: [
                    "error": "\(error)",
                    "orderId": "\(orderId)"
                ])
                completion(.failure(error))
            }
        }
    }

    /// A buy of a freshly-launched currency, funded by the caller's USDF VM
    /// (Phase 1 + Phase 2 via IntentFundSwap). Mirrors `buy(...)` but takes a
    /// raw `mint: PublicKey` because the currency is too new to have
    /// `MintMetadata` hydrated locally.
    ///
    /// The funding intent transfers `amount + feeAmount` USDF to the VM swap
    /// PDA; the server splits that total into the swap (minting tokens) and
    /// the launch fee via `TransferForSwapWithFee`.
    func buyNewCurrency(
        swapId: SwapId,
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        verifiedState: VerifiedState,
        mint: PublicKey,
        owner: AccountCluster,
        completion: @Sendable @escaping (Result<SwapMetadata, ErrorSwap>) -> Void
    ) {
        guard let fundingIntentID = PublicKey.generate() else {
            completion(.failure(.unknown))
            return
        }
        let ownerKeyPair = owner.authority.keyPair

        let fundingAmount = amount.adding(feeAmount)

        logger.info("Starting new-currency buy", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "feeAmount": "\(feeAmount.nativeAmount.formatted())",
            "fundingAmount": "\(fundingAmount.nativeAmount.formatted())",
            "mint": "\(mint.base58)",
            "swapId": "\(swapId.publicKey.base58)",
        ])

        // Phase 1: Create swap state on the server
        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: .launchStub(address: mint)),
            amount: amount.onChainAmount,
            feeAmount: feeAmount.onChainAmount,
            fundingSource: .submitIntent(id: fundingIntentID),
            owner: ownerKeyPair,
            isNewCurrencyLaunch: true
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let metadata):
                logger.info("New-currency swap state created", metadata: [
                    "swapId": "\(metadata.swapId.publicKey.base58)",
                ])

                // Phase 2: Fund the VM swap PDA via IntentFundSwap.
                let fundingIntent = IntentFundSwap(
                    intentID: fundingIntentID,
                    swapId: metadata.swapId,
                    sourceCluster: owner,
                    amount: fundingAmount,
                    verifiedState: verifiedState,
                    fromMint: .usdf,
                    toMint: .usdf
                )

                self.submit(intent: fundingIntent, owner: ownerKeyPair) { fundingResult in
                    switch fundingResult {
                    case .success:
                        logger.info("New-currency buy completed", metadata: [
                            "intentId": "\(fundingIntentID.base58)",
                        ])
                        completion(.success(metadata))
                    case .failure(let error):
                        logger.error("Failed to fund new-currency swap", metadata: ["error": "\(error)"])
                        completion(.failure(.fundingIntent(error)))
                    }
                }

            case .failure(let error):
                logger.error("Failed to start new-currency swap", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    /// Runs a stateless USDC ↔ USDF swap via Coinbase Stable Swapper. Used by
    /// the on-app-open auto-sweep.
    func statelessSwap(
        fromMint: MintMetadata,
        toMint: MintMetadata,
        amount: TokenAmount,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<StatelessSwapResult, ErrorStatelessSwap>) -> Void
    ) {
        swapService.statelessSwap(
            fromMint: fromMint,
            toMint: toMint,
            amount: amount,
            owner: owner,
            completion: completion
        )
    }

    /// A sell is a swap from token to USDF
    func sell(amount: ExchangedFiat, verifiedState: VerifiedState, in token: MintMetadata, owner: AccountCluster, completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void) {
        logger.info("Starting sell", metadata: [
            "symbol": "\(token.symbol)",
            "amount": "\(amount.nativeAmount.formatted())"
        ])

        // Generate unique identifiers for this swap
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey

        guard let tokenVmAuthority = token.vmMetadata?.authority else {
            logger.error("Failed to find VM authority for token", metadata: [
                "symbol": "\(token.symbol)",
                "mint": "\(token.address.base58)"
            ])
            completion(.failure(.unknown))
            return
        }

        // Phase 1: StartSwap - Create swap state and reserve nonce + blockhash
        swapService.swap(
            swapId: swapId,
            direction: .sell(mint: token),
            amount: amount.onChainAmount,
            fundingSource: .submitIntent(id: fundingIntentID),
            owner: owner.authority.keyPair
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let metadata):
                logger.info("Swap state created", metadata: ["swapId": "\(swapId.publicKey.base58)"])

                // Phase 2: SubmitIntent - Fund the VM swap PDA
                let fundingIntent = IntentFundSwap(
                    intentID: fundingIntentID,
                    swapId: metadata.swapId,
                    sourceCluster: owner.use(mint: token.address, timeAuthority: tokenVmAuthority),
                    amount: amount,
                    verifiedState: verifiedState,
                    fromMint: token,
                    toMint: .usdf
                )

                self.submit(intent: fundingIntent, owner: owner.authority.keyPair) { fundingResult in
                    switch fundingResult {
                    case .success:
                        logger.info("Sell swap completed", metadata: ["intentId": "\(fundingIntentID.base58)"])
                        completion(.success(swapId))

                    case .failure(let error):
                        logger.error("Failed to fund sell swap", metadata: ["error": "\(error)"])
                        completion(.failure(.fundingIntent(error)))
                    }
                }

            case .failure(let error):
                logger.error("Failed to start sell swap", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    // MARK: - Submit -

    private func submit<T>(intent: T, owner: KeyPair, deviceToken: Data? = nil, completion: @Sendable @escaping (Result<T, ErrorSubmitIntent>) -> Void) where T: IntentType {
        logger.info("Submitting intent", metadata: ["type": "\(T.self)", "intentId": "\(intent.id.base58)"])

        // `IntentType` is a reference type that is not `Sendable`; the response
        // handler mutates it (`apply(parameters:)`) within the single-threaded
        // server ping-pong, so the captured reference is safe to share.
        nonisolated(unsafe) let intent = intent

        let reference = BidirectionalStream()

        reference.open(onResponse: { response in
            switch response.response {

            // Upon successful submission of intent action the server will
            // respond with parameters that we'll need to apply to the intent
            // before crafting and signing the transactions.
            case .serverParameters(let parameters):
                do {
                    let serverParameters = try parameters.serverParameters.map {
                        try ServerParameter($0)
                    }

                    try intent.apply(parameters: serverParameters)

                    let submitSignatures = try intent.requestToSubmitSignatures()
                    reference.sendMessage(submitSignatures)

                    logger.info("Received server parameters, submitting signatures", metadata: [
                        "type": "\(T.self)",
                        "paramCount": "\(parameters.serverParameters.count)",
                        "intentId": "\(intent.id.base58)"
                    ])

                } catch {
                    logger.error("Received server parameters but failed to apply them", metadata: [
                        "type": "\(T.self)",
                        "paramCount": "\(parameters.serverParameters.count)",
                        "intentId": "\(intent.id.base58)",
                        "error": "\(error)"
                    ])
                    reference.cancel()
                    completion(.failure(.unknown))
                }

            // If submitted transaction signatures are valid and match
            // the server, we'll receive a success for the submitted intent.
            case .success(let success):
                logger.info("Intent submitted successfully", metadata: [
                    "type": "\(T.self)",
                    "code": "\(success.code.rawValue)",
                    "intentId": "\(intent.id.base58)"
                ])
                reference.cancel()
                completion(.success(intent))

            // If the submitted transaction signatures don't match, the
            // intent is considered failed. Something must have gone wrong
            // on the transaction creation or signing on our side.
            case .error(let error):
                let invalidSignatures = error.errorDetails.compactMap { details -> String? in
                    switch details.type {
                    case .invalidSignature(let signatureDetails):
                        let signature = (try? Signature(signatureDetails.providedSignature.value).base58) ?? "nil"
                        return "action=\(signatureDetails.actionID) signature=\(signature) transaction=\(signatureDetails.expectedTransaction.value.hexEncodedString())"
                    default:
                        return nil
                    }
                }

                logger.error("Intent submission error", metadata: [
                    "type": "\(T.self)",
                    "code": "\(error.code)",
                    "detailCount": "\(error.errorDetails.count)",
                    "intentId": "\(intent.id.base58)",
                    "invalidSignatures": "\(invalidSignatures)"
                ])

                reference.cancel()
                let intentError = ErrorSubmitIntent(error: error)
                completion(.failure(intentError))

            default:
                reference.cancel()
                completion(.failure(.unknown))
            }
        }, onComplete: { result in
            // TODO: Fix gRPC validation failures
            // If client's response fails gRPC validation, the request
            // will fail in the block below and the completion won't get
            // called. We should handle that case more gracefully and ensure
            // it's robust.
            switch result {
            case .success:
                logger.info("Intent stream closed")
                // Completion called in the success block

            case .failure(let error as RPCError):
                logger.warning("Intent stream closed with non-OK status", metadata: [
                    "code": "\(error.code)",
                    "message": "\(error.message)"
                ])
                completion(.failure(.grpcStatus(error)))

            case .failure(let error):
                logger.error("Intent stream closed with gRPC error", metadata: ["error": "\(error)"])
                completion(.failure(.grpcError(error)))
            }
        }) { requests, onResponse in
            try await self.service.submitIntent(
                requestProducer: { writer in
                    for await request in requests {
                        try await writer.write(request)
                    }
                },
                onResponse: { streamResponse in
                    for try await message in streamResponse.messages {
                        onResponse(message)
                    }
                }
            )
        }

        // Send `submitActions` request with actions generated by the intent
        // Log action-level details to verify we are opening the expected account
        intent.actions.enumerated().forEach { idx, action in
            if let open = action as? ActionOpenAccount {
                logger.info("Action OpenAccount", metadata: [
                    "index": "\(idx)",
                    "owner": "\(open.owner.base58)",
                    "authority": "\(open.cluster.authority.keyPair.publicKey.base58)",
                    "vault": "\(open.cluster.vaultPublicKey.base58)",
                    "mint": "\(open.mint.base58)",
                    "derivationIndex": "\(open.derivationIndex)"
                ])
            } else if let transfer = action as? ActionTransfer {
                logger.info("Action Transfer", metadata: [
                    "index": "\(idx)",
                    "quarks": "\(transfer.amount.quarks)",
                    "destination": "\(transfer.destination.base58)"
                ])
            } else {
                logger.info("Action", metadata: [
                    "index": "\(idx)",
                    "type": "\(type(of: action))"
                ])
            }
        }

        let submitActions = intent.requestToSubmitActions(owner: owner)
        reference.sendMessage(submitActions)
    }

    // MARK: - Status -

    func fetchIntentMetadata(owner: KeyPair, intentID: PublicKey, completion: @Sendable @escaping (Result<IntentMetadata, ErrorFetchIntentMetadata>) -> Void) {
        let request = Ocp_Transaction_V1_GetIntentMetadataRequest.with {
            $0.intentID  = intentID.codeIntentID
            $0.owner     = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }

        Task {
            do {
                let response = try await service.getIntentMetadata(request, options: .unaryDefault)
                let result = ErrorFetchIntentMetadata(rawValue: response.result.rawValue) ?? .unknown
                guard result == .ok else {
                    await MainActor.run { completion(.failure(result)) }
                    return
                }

                do {
                    let metadata = try IntentMetadata(response.metadata)
                    logger.info("Intent metadata fetched successfully", metadata: ["intentId": "\(intentID.base58)"])
                    await MainActor.run { completion(.success(metadata)) }
                } catch {
                    logger.error("Failed to parse intent metadata", metadata: [
                        "intentId": "\(intentID.base58)",
                        "error": "\(error)"
                    ])
                    await MainActor.run { completion(.failure(.failedToParse)) }
                }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(ErrorFetchIntentMetadata.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    // MARK: - Limits -

    func fetchTransactionLimits(owner: KeyPair, since date: Date, completion: @Sendable @escaping (Result<Limits, ErrorFetchLimits>) -> Void) {
        logger.info("Fetching transaction limits", metadata: [
            "owner": "\(owner.publicKey.base58)",
            "since": "\(date.description(with: .current))"
        ])

        let fetchDate: Date = .now

        let request = Ocp_Transaction_V1_GetLimitsRequest.with {
            $0.owner         = owner.publicKey.solanaAccountID
            $0.consumedSince = .init(date: date)
            $0.signature     = $0.sign(with: owner)
        }

        Task {
            do {
                let response = try await service.getLimits(request, options: .unaryDefault)
                let error = ErrorFetchLimits(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to fetch transaction limits", metadata: [
                        "owner": "\(owner.publicKey.base58)",
                        "since": "\(date.description(with: .current))",
                        "error": "\(error)"
                    ])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }

                let limits = Limits(
                    proto: response,
                    sinceDate: date,
                    fetchDate: fetchDate
                )

                logger.info("Transaction limits fetched successfully", metadata: [
                    "owner": "\(owner.publicKey.base58)"
                ])
                await MainActor.run { completion(.success(limits)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(ErrorFetchLimits.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }

    // MARK: - Withdrawals -

    func fetchDestinationMetadata(destination: PublicKey, mint: PublicKey, completion: @Sendable @escaping (Result<DestinationMetadata, Never>) -> Void) {
        logger.info("Fetching destination metadata", metadata: ["destination": "\(destination.base58)"])

        let request = Ocp_Transaction_V1_CanWithdrawToAccountRequest.with {
            $0.account = destination.solanaAccountID
            $0.mint    = mint.solanaAccountID
        }

        Task {
            do {
                let response = try await service.canWithdrawToAccount(request, options: .unaryDefault)

                let metadata = DestinationMetadata(
                    kind: .init(rawValue: response.accountType.rawValue) ?? .unknown,
                    destination: destination,
                    mint: mint,
                    isValid: response.isValidPaymentDestination,
                    requiresInitialization: response.requiresInitialization,
                    fee: response.requiresInitialization ? TokenAmount(
                        wholeTokens: Decimal(response.feeAmount.nativeAmount),
                        mint: mint,
                    ) : .zero(mint: mint)
                )

                await MainActor.run { completion(.success(metadata)) }

            } catch {

                let metadata = DestinationMetadata(
                    kind: .unknown,
                    destination: destination,
                    mint: mint,
                    isValid: false,
                    requiresInitialization: false,
                    fee: .zero(mint: mint)
                )

                await MainActor.run { completion(.success(metadata)) }
            }
        }
    }
}

// MARK: - Types -

public struct DestinationMetadata: Sendable {

    public let destination: Destination
    public let isValid: Bool
    public let kind: Kind
    public let fee: TokenAmount

    public let requiresInitialization: Bool

    init(kind: Kind, destination: PublicKey, mint: PublicKey, isValid: Bool, requiresInitialization: Bool, fee: TokenAmount) {
        switch kind {
        case .unknown, .token:
            self.destination = .init(token: destination)

        case .owner:
            self.destination = .init(owner: destination, mint: mint)
        }

        self.kind = kind
        self.isValid = isValid
        self.requiresInitialization = requiresInitialization
        self.fee = fee
    }
}

extension DestinationMetadata {
    public enum Kind: Int, Sendable {
        case unknown
        case token
        case owner
    }

    public struct Destination: Sendable {
        public let owner: PublicKey?
        public let token: PublicKey
        public let requiredResolution: Bool

        init(token: PublicKey) {
            self.owner = nil
            self.token = token
            self.requiredResolution = false
        }

        init(owner: PublicKey, mint: PublicKey) {
            self.owner = owner
            self.token = AssociatedTokenAccount(owner: owner, mint: mint).ata.publicKey
            self.requiredResolution = true
        }
    }
}

// MARK: - Errors -

public enum ErrorSubmitIntent: Error, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    /// Proto-code-backed denial reason. Maps 1:1 to DeniedErrorDetails.Code.
    public enum DeniedReason: Int, Sendable {
        /// No reason is available
        case unspecified // = 0
    }

    /// Semantic categorization of staleState reason strings. Extended
    /// whenever a call site needs to branch on a specific server message.
    public enum StaleStateKind: Sendable, Equatable {
        /// Server reports the gift card was already claimed/voided/expired —
        /// a benign race when another device redeemed first.
        case alreadyClaimed

        public init?(serverReason: String) {
            let reason = serverReason.lowercased()
            if reason.contains("already been claimed") || reason.contains("already claimed") {
                self = .alreadyClaimed
                return
            }
            return nil
        }
    }

    /// Denied by a guard (spam, money laundering, etc)
    case denied([DeniedReason], messages: [String])
    /// The intent is invalid.
    case invalidIntent([String])
    /// There is an issue with provided signatures.
    case signatureError
    /// Server detected client has stale state.
    case staleState([String], kinds: Set<StaleStateKind>)
    /// Unknown reason
    case unknown //= -1
    /// Device token unavailable
    case deviceTokenUnavailable //= -2
    /// gRPC status
    case grpcStatus(RPCError)
    /// gRPC error
    case grpcError(Error)

    init(error: Ocp_Transaction_V1_SubmitIntentResponse.Error) {
        let reasonStrings: [String] = error.errorDetails.compactMap {
            if case .reasonString(let object) = $0.type {
                return !object.reason.isEmpty ? object.reason : nil
            } else {
                return nil
            }
        }

        switch error.code {
        case .denied:
            var reasons: [DeniedReason] = []
            var messages: [String] = []
            for details in error.errorDetails {
                if case .denied(let deniedDetails) = details.type {
                    if let reason = DeniedReason(rawValue: deniedDetails.code.rawValue) {
                        reasons.append(reason)
                    }
                    if !deniedDetails.reason.isEmpty {
                        messages.append(deniedDetails.reason)
                    }
                }
            }
            self = .denied(reasons, messages: messages)

        case .invalidIntent:
            self = .invalidIntent(reasonStrings)

        case .signatureError:
            self = .signatureError

        case .staleState:
            var kinds: Set<StaleStateKind> = []
            for reason in reasonStrings {
                if let kind = StaleStateKind(serverReason: reason) {
                    kinds.insert(kind)
                }
            }
            self = .staleState(reasonStrings, kinds: kinds)

        case .UNRECOGNIZED:
            self = .unknown
        }
    }

    public var description: String {
        switch self {
        case .denied(let reasons, let messages):
            let reasonString = reasons.map { "\($0)" }.joined(separator: ", ")
            if messages.isEmpty {
                return "denied(\(reasonString))"
            }
            return "denied(\(reasonString): \(messages.joined(separator: "; ")))"
        case .invalidIntent(let reasons):
            return "invalidIntent(\(reasons.joined(separator: ", ")))"
        case .signatureError:
            return "signatureError"
        case .staleState(let reasons, _):
            return "staleState(\(reasons.joined(separator: ", ")))"
        case .unknown:
            return "unknown"
        case .deviceTokenUnavailable:
            return "deviceTokenUnavailable"
        case .grpcStatus(let status):
            return "grpcStatus(\(status.code.rawValue))"
        case .grpcError(let error):
            return "grpcError(\(error.localizedDescription))"
        }
    }

    public var debugDescription: String {
        description
    }
}

public enum ErrorVoidGiftCard: Int, Error {
    case ok
    case denied
    case claimed
    case notFound
    case unknown = -1
    case transportFailure = -2
    case cancelled = -3
}

public enum ErrorFetchIntentMetadata: Int, Error {
    case ok
    case notFound
    case denied
    case unknown = -1
    case failedToParse = -2
    case transportFailure = -3
    case cancelled = -4
}

public enum ErrorFetchLimits: Int, Error {
    case ok
    case unknown = -1
    case transportFailure = -2
    case cancelled = -3
}

extension ErrorSubmitIntent: ServerError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .denied, .invalidIntent, .staleState: .info
        case .signatureError, .unknown, .deviceTokenUnavailable, .grpcError: .error
        case .grpcStatus(let status): status.reportingLevel
        }
    }
}

extension ErrorVoidGiftCard: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .claimed, .notFound: .info
        case .unknown: .error
        }
    }
}

extension ErrorFetchIntentMetadata: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .notFound, .denied: .info
        case .unknown, .failedToParse: .error
        }
    }
}

extension ErrorFetchLimits: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .unknown: .error
        }
    }
}
