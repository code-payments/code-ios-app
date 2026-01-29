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

class TransactionService: CodeService<Ocp_Transaction_V1_TransactionNIOClient> {
    typealias BidirectionalStream = BidirectionalStreamReference<Ocp_Transaction_V1_SubmitIntentRequest, Ocp_Transaction_V1_SubmitIntentResponse>
    
    // Swap service for managing token swaps
    private(set) lazy var swapService: SwapService = {
        SwapService(channel: channel, queue: queue)
    }()
    
    // MARK: - Account Creation -
    
    func createAccounts(owner: KeyPair, mint: PublicKey, cluster: AccountCluster, kind: AccountKind, derivationIndex: Int, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send)
        
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
                trace(.success)
                completion(.success(()))
                
            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Transfer -

    func transfer(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, sourceCluster: AccountCluster, destination: PublicKey, owner: KeyPair, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send)

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
                trace(.success)
                completion(.success(()))

            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }

    func withdraw(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, fee: Quarks, sourceCluster: AccountCluster, destinationMetadata: DestinationMetadata, owner: KeyPair, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send)

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
                    trace(.success)
                    completion(.success(()))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            trace(.failure, components: "Intent error: \(error)")
            completion(.failure(error))
        }
    }
    
    func sendCashLink(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, ownerCluster: AccountCluster, giftCard: GiftCardCluster, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send, components: "Gift card vault: \(giftCard.cluster.vaultPublicKey.base58)", "Amount: \(exchangedFiat.underlying.formatted(suffix: " USDF"))")

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
                trace(.success)
                completion(.success(()))

            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    func receiveCashLink(usdf: Quarks, ownerCluster: AccountCluster, giftCard: GiftCardCluster, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send, components: "Gift card vault: \(giftCard.cluster.vaultPublicKey.base58)", "Amount: \(usdf.formatted(suffix: " USDF"))")
        
        let intent = IntentReceiveCashLink(
            ownerCluster: ownerCluster,
            giftCard: giftCard,
            usdf: usdf
        )
        
        submit(intent: intent, owner: ownerCluster.authority.keyPair) { result in
            switch result {
            case .success(_):
                trace(.success)
                completion(.success(()))
                
            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    func voidCashLink(giftCardVault: PublicKey, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorVoidGiftCard>) -> Void) {
        trace(.send, components: "Gift card: \(giftCardVault.base58)")
        
        let request = Ocp_Transaction_V1_VoidGiftCardRequest.with {
            $0.giftCardVault = giftCardVault.solanaAccountID
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.voidGiftCard(request)
        call.handle(on: queue) { response in
            let error = ErrorVoidGiftCard(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Gift card: \(giftCardVault.base58)")
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { _ in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - AirDrop -
    
    func airdrop(type: AirdropType, owner: KeyPair, completion: @Sendable @escaping (Result<PaymentMetadata, ErrorAirdrop>) -> Void) {
        trace(.send)
        
        let request = Ocp_Transaction_V1_AirdropRequest.with {
            $0.airdropType = type.grpcType
            $0.owner = owner.publicKey.solanaAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.airdrop(request)
        call.handle(on: queue) { response in
            
            let result = ErrorAirdrop(rawValue: response.result.rawValue) ?? .unknown
            guard result == .ok else {
                trace(.failure, components: "Error: \(result)")
                completion(.failure(result))
                return
            }
            
            do {
                let exchangedFiat = try ExchangedFiat(response.exchangeData)
                let metadata = PaymentMetadata(exchangedFiat: exchangedFiat)
                trace(.success, components: "Received: USD \(exchangedFiat.underlying.formatted(suffix: nil))")
                completion(.success(metadata))
            } catch {
                trace(.failure, components: "Failed to parse metadata.")
                completion(.failure(.unknown))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Swaps -

    /// A buy is a swap from USDF to desired token (convenience method using submitIntent funding)
    func buy(amount: ExchangedFiat, verifiedState: VerifiedState, of token: MintMetadata, owner: AccountCluster, completion: @Sendable @escaping (Result<Void, ErrorSwap>) -> Void) {
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey

        buy(
            swapId: swapId,
            amount: amount,
            verifiedState: verifiedState,
            of: token,
            owner: owner,
            fundingSource: .submitIntent(id: fundingIntentID),
            completion: completion
        )
    }

    /// A buy is a swap from USDF to desired token with specified funding source.
    ///
    /// - For `.submitIntent`: Phase 1 (startSwap) + Phase 2 (IntentFundSwap)
    /// - For `.externalWallet`: Phase 1 only (funding already happened via external wallet)
    func buy(
        swapId: SwapId,
        amount: ExchangedFiat,
        verifiedState: VerifiedState,
        of token: MintMetadata,
        owner: AccountCluster,
        fundingSource: FundingSource,
        completion: @Sendable @escaping (Result<Void, ErrorSwap>) -> Void
    ) {
        trace(.send, components: "Starting \(amount.converted.formatted()) buy of \(token.symbol) with \(fundingSource)")

        let swapService = self.swapService
        let ownerKeyPair = owner.authority.keyPair

        // Phase 1: StartSwap (always needed)
        swapService.swap(
            swapId: swapId,
            direction: .buy(mint: token),
            amount: amount.underlying,
            fundingSource: fundingSource,
            owner: ownerKeyPair
        ) { result in
            switch result {
            case .success(let metadata):
                trace(.success, components: "Swap state created", "Swap ID: \(swapId.publicKey.base58)")

                switch fundingSource {
                case .submitIntent(let fundingIntentID):
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
                            trace(.success, components: "Swap completed", "Intent ID: \(fundingIntentID.base58)")
                            completion(.success(()))
                        case .failure(let error):
                            trace(.failure, components: "Failed to swap: \(error)")
                            completion(.failure(.unknown))
                        }
                    }

                case .externalWallet:
                    // NO Phase 2 - funding already happened via external wallet
                    trace(.success, components: "Swap initiated with external funding", "Swap ID: \(swapId.publicKey.base58)")
                    completion(.success(()))

                case .unknown:
                    trace(.failure, components: "Unknown funding source")
                    completion(.failure(.unknown))
                }

            case .failure(let error):
                trace(.failure, components: "Failed to start swap: \(error)")
                completion(.failure(error))
            }
        }
    }

    /// A sell is a swap from token to USDF
    func sell(amount: ExchangedFiat, verifiedState: VerifiedState, in token: MintMetadata, owner: AccountCluster, completion: @Sendable @escaping (Result<Void, ErrorSwap>) -> Void) {
        trace(.send, components: "Starting sell of \(token.symbol) for \(amount.converted.formatted())")

        // Generate unique identifiers for this swap
        let swapId = SwapId.generate()
        let fundingIntentID = KeyPair.generate()!.publicKey

        guard let tokenVmAuthority = token.vmMetadata?.authority else {
            trace(.failure, components: "Failed to find vm authority for \(token.symbol)")
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
                trace(.success, components: "Swap state created", "Swap ID: \(swapId.publicKey.base58)")

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
                        trace(.success, components: "Swap completed", "Intent ID: \(fundingIntentID.base58)")
                        completion(.success(()))

                    case .failure(let error):
                        trace(.failure, components: "Failed to fund swap: \(error)")
                        // Map ErrorSubmitIntent to ErrorSwap
                        completion(.failure(.unknown))
                    }
                }

            case .failure(let error):
                trace(.failure, components: "Failed to start swap: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Submit -
    
    private func submit<T>(intent: T, owner: KeyPair, deviceToken: Data? = nil, completion: @Sendable @escaping (Result<T, ErrorSubmitIntent>) -> Void) where T: IntentType {
        trace(.send, components: "Type: \(T.self)", "Submitting intent: \(intent.id.base58)")
        
        let reference = BidirectionalStream()
        
        // Intentionally creates a retain-cycle using closures to ensure that we have
        // a strong reference to the stream at all times. Doing so ensures that the
        // callers don't have to manage the pointer to this stream and keep it alive
        reference.retain()
        
        reference.stream = service.submitIntent { result in
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
                    
                    trace(.receive, components: "Type: \(T.self)", "Received \(parameters.serverParameters.count) parameters. Submitting signatures...", "Intent: \(intent.id.base58)")
                    
                } catch {
                    trace(.failure, components: "Type: \(T.self)", "Received \(parameters.serverParameters.count) parameters but failed to apply them: \(error)", "Intent: \(intent.id.base58)")
                    completion(.failure(.unknown))
                }
                
            // 3. If submitted transaction signatures are valid and match
            // the server, we'll receive a success for the submitted intent.
            case .success(let success):
                trace(.success, components: "Type: \(T.self)", "Success: \(success.code.rawValue)", "Intent: \(intent.id.base58)")
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
                
                trace(.failure, components: container)
                
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
                    trace(.success, components: "Stream closed")
                    // Completion called in the success block
                } else {
                    trace(.warning, components: "Stream closed: \(status)")
                    completion(.failure(.grpcStatus(status)))
                }
                
            case .failure(let error):
                trace(.failure, components: "GRPC Error - stream closed: \(error)")
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
                trace(.send, components: "Action[\(idx)]: OpenAccount", "owner: \(open.owner.base58)", "authority: \(open.cluster.authority.keyPair.publicKey.base58)", "token: \(open.cluster.vaultPublicKey.base58)", "mint: \(open.mint.base58)", "index: \(open.derivationIndex)")
            } else if let transfer = action as? ActionTransfer {
                trace(.send, components: "Action[\(idx)]: Transfer", "quarks: \(transfer.amount.quarks)", "destination: \(transfer.destination.base58)")
            } else {
                trace(.send, components: "Action[\(idx)]: \(type(of: action))")
            }
        }

        let submitActions = intent.requestToSubmitActions(owner: owner)
        do {
            let bytes = try submitActions.serializedData()
            trace(.send, components: "Type: \(T.self)", "Submitting submitActions proto (hex): \(bytes.hexEncodedString())")
        } catch {
            trace(.warning, components: "Type: \(T.self)", "Failed to serialize submitActions for logging: \(error)")
        }

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
                trace(.success, components: "Intent Successful: \(intentID.base58)")
                completion(.success(metadata))
            } catch {
                trace(.failure, components: "Failed to parse metadata: \(response.metadata)")
                completion(.failure(.failedToParse))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Limits -
    
    func fetchTransactionLimits(owner: KeyPair, since date: Date, completion: @Sendable @escaping (Result<Limits, ErrorFetchLimits>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Since (local): \(date.description(with: .current))")
        
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
                trace(.failure, components: "Owner: \(owner.publicKey.base58)", "Since (local): \(date.description(with: .current))", "Error: \(error)")
                completion(.failure(error))
                return
            }
            
            let limits = Limits(
                proto: response,
                sinceDate: date,
                fetchDate: fetchDate
            )
            
            trace(.success, components: "Owner: \(owner.publicKey.base58)", "Since (local): \(date.description(with: .current))")
            completion(.success(limits))
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Withdrawals -
    
    func fetchDestinationMetadata(destination: PublicKey, mint: PublicKey, completion: @Sendable @escaping (Result<DestinationMetadata, Never>) -> Void) {
        trace(.send, components: "Destination: \(destination.base58)")
        
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
    public enum DeniedReason: Int, Sendable {
        /// No reason is available
        case unspecified // = 0
        /// Phone number has exceeded its free account allocation
        case tooManyFreeAccountsForPhoneNumber // = 1
        /// Device has exceeded its free account allocation
        case tooManyFreeAccountsForDevice // = 2
        /// The country associated with the phone number with the account is not
        /// supported (eg. it is on the sanctioned list).
        case unsupportedCountry // = 3
        /// The device is not supported (eg. it fails device attestation checks)
        case unsupportedDevice // = 4
    }
    
    /// Denied by a guard (spam, money laundering, etc)
    case denied([DeniedReason])
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
            let reasons: [DeniedReason] = error.errorDetails.compactMap {
                if case .denied(let details) = $0.type {
                    return DeniedReason(rawValue: details.code.rawValue)
                } else {
                    return nil
                }
            }
            
            self = .denied(reasons)
            
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
        case .denied(let reasons):
            let string = reasons.map { "\($0)" }.joined(separator: ", ")
            return "denied(\(string))"
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
    case unknown = -1
    case failedToParse = -2
}

public enum ErrorFetchLimits: Int, Error {
    case ok
    case unknown = -1
}

public enum ErrorAirdrop: Int, Error {
    case ok
    case unavailable
    case alreadyClaimed
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Ocp_Transaction_V1_TransactionClientInterceptorFactoryProtocol {
    func makeVoidGiftCardInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Transaction_V1_VoidGiftCardRequest, FlipcashAPI.Ocp_Transaction_V1_VoidGiftCardResponse>] {
        makeInterceptors()
    }
    
    func makeAirdropInterceptors() -> [GRPC.ClientInterceptor<Ocp_Transaction_V1_AirdropRequest, Ocp_Transaction_V1_AirdropResponse>] {
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
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
