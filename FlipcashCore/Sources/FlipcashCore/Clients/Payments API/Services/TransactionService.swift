//
//  TransactionService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import Combine
import GRPC
import SwiftProtobuf
import NIO
import DeviceCheck

private let logger = Logger(label: "flipcash.transaction-service")

class TransactionService: CodeService<Ocp_Transaction_V1_TransactionNIOClient> {
    typealias BidirectionalStream = BidirectionalStreamReference<Ocp_Transaction_V1_SubmitIntentRequest, Ocp_Transaction_V1_SubmitIntentResponse>
    
    // Swap service for managing token swaps
    private(set) lazy var swapService: SwapService = {
        SwapService(channel: channel, queue: queue)
    }()
    
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
                logger.error("Failed to create accounts: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Transfer -

    func transfer(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, sourceCluster: AccountCluster, destination: PublicKey, owner: KeyPair, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Sending transfer")

        let intent = IntentTransfer(
            rendezvous: rendezvous,
            sourceCluster: sourceCluster,
            destination: destination,
            exchangedFiat: exchangedFiat,
            verifiedState: verifiedState
        )

        submit(intent: intent, owner: owner) { result in
            switch result {
            case .success(_):
                logger.info("Transfer succeeded")
                completion(.success(()))

            case .failure(let error):
                logger.error("Transfer failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    func withdraw(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, fee: Quarks, sourceCluster: AccountCluster, destinationMetadata: DestinationMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
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
                    logger.error("Withdrawal failed: \(error)")
                    completion(.failure(error))
                }
            }

        } catch {
            logger.error("Failed to build withdraw intent: \(error)")
            completion(.failure(error))
        }
    }
    
    func sendCashLink(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, ownerCluster: AccountCluster, giftCard: GiftCardCluster, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Sending cash link", metadata: [
            "giftCardVault": "\(giftCard.cluster.vaultPublicKey.base58)",
            "amount": "\(exchangedFiat.underlying.formatted(suffix: " USDF"))"
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
                logger.error("Failed to send cash link: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    func receiveCashLink(usdf: Quarks, ownerCluster: AccountCluster, giftCard: GiftCardCluster, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        logger.info("Receiving cash link", metadata: [
            "giftCardVault": "\(giftCard.cluster.vaultPublicKey.base58)",
            "amount": "\(usdf.formatted(suffix: " USDF"))"
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
                logger.error("Failed to receive cash link: \(error)")
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

        let call = service.voidGiftCard(request)
        call.handle(on: queue) { response in
            let error = ErrorVoidGiftCard(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("Cash link voided", metadata: ["giftCard": "\(giftCardVault.base58)"])
                completion(.success(()))
            } else {
                logger.error("Failed to void cash link: \(error)")
                completion(.failure(error))
            }

        } failure: { _ in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Swaps -

    /// A buy is a swap from USDF to desired token (Phase 1 + Phase 2 via IntentFundSwap)
    func buy(amount: ExchangedFiat, verifiedState: VerifiedState, of token: MintMetadata, owner: AccountCluster, completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void) {
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey
        let ownerKeyPair = owner.authority.keyPair

        logger.info("Starting buy", metadata: [
            "amount": "\(amount.converted.formatted())",
            "symbol": "\(token.symbol)"
        ])

        // Phase 1: Create swap state on the server
        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: token),
            amount: amount.underlying,
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
                        logger.error("Failed to fund buy swap: \(error)")
                        completion(.failure(.unknown))
                    }
                }

            case .failure(let error):
                logger.error("Failed to start buy swap: \(error)")
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
            "amount": "\(amount.converted.formatted())",
            "symbol": "\(token.symbol)",
            "swapId": "\(swapId.publicKey.base58)"
        ])

        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: token),
            amount: amount.underlying,
            fundingSource: .externalWallet(transactionSignature: transactionSignature),
            owner: owner
        ) { result in
            switch result {
            case .success:
                logger.info("Buy swap initiated with external funding", metadata: ["swapId": "\(swapId.publicKey.base58)"])
                completion(.success(swapId))
            case .failure(let error):
                logger.error("Failed to start externally-funded buy swap: \(error)")
                completion(.failure(error))
            }
        }
    }

    /// A sell is a swap from token to USDF
    func sell(amount: ExchangedFiat, verifiedState: VerifiedState, in token: MintMetadata, owner: AccountCluster, completion: @Sendable @escaping (Result<SwapId, ErrorSwap>) -> Void) {
        logger.info("Starting sell", metadata: [
            "symbol": "\(token.symbol)",
            "amount": "\(amount.converted.formatted())"
        ])

        // Generate unique identifiers for this swap
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey

        guard let tokenVmAuthority = token.vmMetadata?.authority else {
            logger.error("Failed to find VM authority for token: \(token.symbol)")
            // Map ErrorSubmitIntent to ErrorSwap
            completion(.failure(.unknown))
            return
        }

        // Phase 1: StartSwap - Create swap state and reserve nonce + blockhash
        swapService.swap(
            swapId: swapId,
            direction: .sell(mint: token),
            amount: amount.underlying,
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
                        logger.error("Failed to fund sell swap: \(error)")
                        // Map ErrorSubmitIntent to ErrorSwap
                        completion(.failure(.unknown))
                    }
                }

            case .failure(let error):
                logger.error("Failed to start sell swap: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Submit -
    
    private func submit<T>(intent: T, owner: KeyPair, deviceToken: Data? = nil, completion: @Sendable @escaping (Result<T, ErrorSubmitIntent>) -> Void) where T: IntentType {
        logger.info("Submitting intent", metadata: ["type": "\(T.self)", "intentId": "\(intent.id.base58)"])
        
        let reference = BidirectionalStream()
        
        // Intentionally creates a retain-cycle using closures to ensure that we have
        // a strong reference to the stream at all times. Doing so ensures that the
        // callers don't have to manage the pointer to this stream and keep it alive
        reference.retain()
        
        reference.stream = service.submitIntent(callOptions: .streaming) { result in
            switch result.response {
                
            // 2. Upon successful submission of intent action the server will
            // respond with parameters that we'll need to apply to the intent
            // before crafting and signing the transactions.
            case .serverParameters(let parameters):
                do {
                    let serverParameters = try parameters.serverParameters.map {
                        try ServerParameter($0)
                    }
                    
                    try intent.apply(parameters: serverParameters)

                    let submitSignatures = try intent.requestToSubmitSignatures()
                    _ = reference.stream?.sendMessage(submitSignatures)

                    logger.info("Received server parameters, submitting signatures", metadata: [
                        "type": "\(T.self)",
                        "paramCount": "\(parameters.serverParameters.count)",
                        "intentId": "\(intent.id.base58)"
                    ])

                } catch {
                    logger.error("Received server parameters but failed to apply them: \(error)", metadata: [
                        "type": "\(T.self)",
                        "paramCount": "\(parameters.serverParameters.count)",
                        "intentId": "\(intent.id.base58)"
                    ])
                    completion(.failure(.unknown))
                }
                
            // 3. If submitted transaction signatures are valid and match
            // the server, we'll receive a success for the submitted intent.
            case .success(let success):
                logger.info("Intent submitted successfully", metadata: [
                    "type": "\(T.self)",
                    "code": "\(success.code.rawValue)",
                    "intentId": "\(intent.id.base58)"
                ])
                _ = reference.stream?.sendEnd()
                completion(.success(intent))
                
            // 3. If the submitted transaction signatures don't match, the
            // intent is considered failed. Something must have gone wrong
            // on the transaction creation or signing on our side.
            case .error(let error):
                var container: [String] = []
                
                container.append("Type: \(T.self)")
                container.append("Code: \(error.code)")
                
                let errors = error.errorDetails.flatMap { details in
                    switch details.type {
                    case .reasonString(let reason):
                        return [
                            "Reason: \(reason.reason)"
                        ]
                        
                    case .invalidSignature(let signatureDetails):
                        return [
                            "Action index: \(signatureDetails.actionID)",
                            "Invalid signature: \((try? Signature(signatureDetails.providedSignature.value).base58) ?? "nil")",
                            "Transaction bytes: \(signatureDetails.expectedTransaction.value.hexEncodedString())",
                        ]
                    default:
                        return []
                    }
                }
                
                container.append(contentsOf: errors)

//                let expectedTransactions = error.errorDetails.compactMap { SolanaTransaction(data: $0.invalidSignature.expectedTransaction.value) }
//                let producedTransactions = intent.actions.flatMap { $0.transactions() }
//                let expectedHashes = expectedTransactions.enumerated().map { "Expected (\($0.0): \(SHA256.digest($0.1.encode()).hexEncodedString())" }
//                let producedHashes = producedTransactions.enumerated().map { "Produced (\($0.0): \(SHA256.digest($0.1.encode()).hexEncodedString())" }
//
//                container.append(contentsOf: expectedHashes)
//                container.append(contentsOf: producedHashes)

                logger.error("Intent submission error: \(container.joined(separator: ", "))")

                _ = reference.stream?.sendEnd()
                let intentError = ErrorSubmitIntent(error: error)
                completion(.failure(intentError))
                
            default:
                _ = reference.stream?.sendEnd()
                completion(.failure(.unknown))
            }
        }
        
        // TODO: Fix gRPC validation failures
        // If client's response fails gRPC validation, the request
        // will fail in the block below and the completion won't get
        // called. We should handle that case more gracefully and ensure
        // it's robust.
        
        reference.stream?.status.whenCompleteBlocking(onto: queue) { result in
            switch result {
            case .success(let status):
                if status.code == .ok {
                    logger.info("Intent stream closed")
                    // Completion called in the success block
                } else {
                    logger.warning("Intent stream closed with non-OK status: \(status)")
                    completion(.failure(.grpcStatus(status)))
                }

            case .failure(let error):
                logger.error("Intent stream closed with gRPC error: \(error)")
                completion(.failure(.grpcError(error)))
            }

            // We release the stream reference after the stream has been
            // closed and there's no further actions required
            reference.release()
        }

        // Send `submitActions` request with actions generated by the intent
        // Log action-level details to verify we are opening the expected account
        intent.actions.enumerated().forEach { idx, action in
            if let open = action as? ActionOpenAccount {
                logger.info("Action[\(idx)]: OpenAccount", metadata: [
                    "owner": "\(open.owner.base58)",
                    "authority": "\(open.cluster.authority.keyPair.publicKey.base58)",
                    "vault": "\(open.cluster.vaultPublicKey.base58)",
                    "mint": "\(open.mint.base58)",
                    "index": "\(open.derivationIndex)"
                ])
            } else if let transfer = action as? ActionTransfer {
                logger.info("Action[\(idx)]: Transfer", metadata: [
                    "quarks": "\(transfer.amount.quarks)",
                    "destination": "\(transfer.destination.base58)"
                ])
            } else {
                logger.info("Action[\(idx)]: \(type(of: action))")
            }
        }

        let submitActions = intent.requestToSubmitActions(owner: owner)
        _ = reference.stream?.sendMessage(submitActions)
    }
    
    // MARK: - Status -
    
    func fetchIntentMetadata(owner: KeyPair, intentID: PublicKey, completion: @Sendable @escaping (Result<IntentMetadata, ErrorFetchIntentMetadata>) -> Void) {
        let request = Ocp_Transaction_V1_GetIntentMetadataRequest.with {
            $0.intentID  = intentID.codeIntentID
            $0.owner     = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getIntentMetadata(request)
        call.handle(on: queue) { response in
            
            let result = ErrorFetchIntentMetadata(rawValue: response.result.rawValue) ?? .unknown
            guard result == .ok else {
                completion(.failure(result))
                return
            }
            
            do {
                let metadata = try IntentMetadata(response.metadata)
                logger.info("Intent metadata fetched successfully", metadata: ["intentId": "\(intentID.base58)"])
                completion(.success(metadata))
            } catch {
                logger.error("Failed to parse intent metadata: \(response.metadata)")
                completion(.failure(.failedToParse))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
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
        
        let call = service.getLimits(request)
        call.handle(on: queue) { response in
            
            let error = ErrorFetchLimits(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to fetch transaction limits: \(error)", metadata: [
                    "owner": "\(owner.publicKey.base58)",
                    "since": "\(date.description(with: .current))"
                ])
                completion(.failure(error))
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
            completion(.success(limits))
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Withdrawals -
    
    func fetchDestinationMetadata(destination: PublicKey, mint: PublicKey, completion: @Sendable @escaping (Result<DestinationMetadata, Never>) -> Void) {
        logger.info("Fetching destination metadata", metadata: ["destination": "\(destination.base58)"])
        
        let request = Ocp_Transaction_V1_CanWithdrawToAccountRequest.with {
            $0.account = destination.solanaAccountID
            $0.mint    = mint.solanaAccountID
        }
        
        let call = service.canWithdrawToAccount(request)
        call.handle(on: queue) { response in
            
            let metadata = DestinationMetadata(
                kind: .init(rawValue: response.accountType.rawValue) ?? .unknown,
                destination: destination,
                mint: mint,
                isValid: response.isValidPaymentDestination,
                requiresInitialization: response.requiresInitialization,
                fee: response.requiresInitialization ? try! Quarks(
                    fiatDecimal: Decimal(response.feeAmount.nativeAmount),
                    currencyCode: .usd,
                    decimals: mint.mintDecimals
                ) : 0
            )
            
            completion(.success(metadata))
            
        } failure: { _ in
            
            let metadata = DestinationMetadata(
                kind: .unknown,
                destination: destination,
                mint: mint,
                isValid: false,
                requiresInitialization: false,
                fee: 0
            )
            
            completion(.success(metadata))
        }
    }
}

// Mark TransactionService as unchecked Sendable to allow using it from @Sendable closures
extension TransactionService: @unchecked Sendable {}

// MARK: - Types -

public struct PoolDistribution {
    
    public let destination: PublicKey
    public var amount: Quarks
    
    public init(destination: PublicKey, amount: Quarks) {
        self.destination = destination
        self.amount = amount
    }
}

public struct DestinationMetadata: Sendable {
    
    public let destination: Destination
    public let isValid: Bool
    public let kind: Kind
    public let fee: Quarks
    
    public let requiresInitialization: Bool
    
    init(kind: Kind, destination: PublicKey, mint: PublicKey, isValid: Bool, requiresInitialization: Bool, fee: Quarks) {
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

    /// Denied by a guard (spam, money laundering, etc)
    case denied([DeniedReason], messages: [String])
    /// The intent is invalid.
    case invalidIntent([String])
    /// There is an issue with provided signatures.
    case signatureError
    /// Server detected client has stale state.
    case staleState([String])
    /// Unknown reason
    case unknown //= -1
    /// Device token unavailable
    case deviceTokenUnavailable //= -2
    /// gRPC status
    case grpcStatus(GRPCStatus)
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
            self = .staleState(reasonStrings)

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
        case .staleState(let reasons):
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
}

public enum ErrorFetchIntentMetadata: Int, Error {
    case ok
    case notFound
    case denied
    case unknown = -1
    case failedToParse = -2
}

public enum ErrorFetchLimits: Int, Error {
    case ok
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Ocp_Transaction_V1_TransactionClientInterceptorFactoryProtocol {
    func makeVoidGiftCardInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Transaction_V1_VoidGiftCardRequest, FlipcashAPI.Ocp_Transaction_V1_VoidGiftCardResponse>] {
        makeInterceptors()
    }
        
    func makeCanWithdrawToAccountInterceptors() -> [GRPC.ClientInterceptor<Ocp_Transaction_V1_CanWithdrawToAccountRequest, Ocp_Transaction_V1_CanWithdrawToAccountResponse>] {
        makeInterceptors()
    }
    
    func makeGetIntentMetadataInterceptors() -> [GRPC.ClientInterceptor<Ocp_Transaction_V1_GetIntentMetadataRequest, Ocp_Transaction_V1_GetIntentMetadataResponse>] {
        makeInterceptors()
    }
    
    func makeGetLimitsInterceptors() -> [GRPC.ClientInterceptor<Ocp_Transaction_V1_GetLimitsRequest, Ocp_Transaction_V1_GetLimitsResponse>] {
        makeInterceptors()
    }
    
    func makeSubmitIntentInterceptors() -> [GRPC.ClientInterceptor<Ocp_Transaction_V1_SubmitIntentRequest, Ocp_Transaction_V1_SubmitIntentResponse>] {
        makeInterceptors()
    }
        
    func makeStatefulSwapInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Transaction_V1_StatefulSwapRequest, FlipcashAPI.Ocp_Transaction_V1_StatefulSwapResponse>] {
        makeInterceptors()
    }
    
    func makeGetSwapInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Transaction_V1_GetSwapRequest, FlipcashAPI.Ocp_Transaction_V1_GetSwapResponse>] {
        makeInterceptors()
    }
    
    func makeGetPendingSwapsInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Transaction_V1_GetPendingSwapsRequest, FlipcashAPI.Ocp_Transaction_V1_GetPendingSwapsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Ocp_Transaction_V1_TransactionNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
