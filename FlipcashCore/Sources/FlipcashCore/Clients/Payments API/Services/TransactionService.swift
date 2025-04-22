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

class TransactionService: CodeService<Code_Transaction_V2_TransactionNIOClient> {
    
    typealias BidirectionalStream = BidirectionalStreamReference<Code_Transaction_V2_SubmitIntentRequest, Code_Transaction_V2_SubmitIntentResponse>
    
    // MARK: - Account Creation -
    
    func createAccounts(with owner: AccountCluster, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send)
        
        let intent = IntentCreateAccount(owner: owner)
        
        submit(intent: intent, owner: owner.authority.keyPair) { result in
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
    
    func transfer(exchangedFiat: ExchangedFiat, sourceCluster: AccountCluster, destination: PublicKey, owner: KeyPair, rendezvous: PublicKey, completion: @Sendable @escaping (Result<(), Error>) -> Void) {
        trace(.send)
        
        let intent = IntentTransfer(
            rendezvous: rendezvous,
            sourceCluster: sourceCluster,
            destination: destination,
            exchangedFiat: exchangedFiat
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
    
//    func withdraw(amount: KinAmount, organizer: Organizer, destination: PublicKey, completion: @escaping (Result<IntentPublicTransfer, Error>) -> Void) {
//        trace(.send)
//        
//        do {
//            let intent = try IntentPublicTransfer(
//                organizer: organizer,
//                source: .primary,
//                destination: .external(destination),
//                amount: amount
//            )
//            
//            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
//                switch result {
//                case .success(let intent):
//                    trace(.success)
//                    completion(.success(intent))
//                    
//                case .failure(let error):
//                    trace(.failure, components: "Error: \(error)")
//                    completion(.failure(error))
//                }
//            }
//            
//        } catch {
//            completion(.failure(error))
//        }
//    }
    
    // MARK: - Remote Send -
    
//    func sendRemotely(amount: KinAmount, organizer: Organizer, rendezvous: PublicKey, giftCard: GiftCardAccount, completion: @escaping (Result<IntentRemoteSend, Error>) -> Void) {
//        trace(.send)
//        
//        do {
//            let intent = try IntentRemoteSend(
//                rendezvous: rendezvous,
//                organizer: organizer,
//                giftCard: giftCard,
//                amount: amount
//            )
//            
//            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
//                switch result {
//                case .success(let intent):
//                    trace(.success)
//                    completion(.success(intent))
//                    
//                case .failure(let error):
//                    trace(.failure, components: "Error: \(error)")
//                    completion(.failure(error))
//                }
//            }
//            
//        } catch {
//            completion(.failure(error))
//        }
//    }
    
    // MARK: - AirDrop -
    
    func airdrop(type: AirdropType, owner: KeyPair, completion: @Sendable @escaping (Result<PaymentMetadata, ErrorAirdrop>) -> Void) {
        trace(.send)
        
        let request = Code_Transaction_V2_AirdropRequest.with {
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
                trace(.success, components: "Received: USD \(exchangedFiat.usdc.formatted(suffix: nil))")
                completion(.success(metadata))
            } catch {
                trace(.failure, components: "Failed to parse metadata.")
                completion(.failure(.unknown))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
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
                            "Invalid signature: \(Signature(signatureDetails.providedSignature.value)?.base58 ?? "nil")",
                            "Transaction bytes: \(signatureDetails.expectedTransaction.value.hexEncodedString())",
                            "Transaction expected: \(SolanaTransaction(data: signatureDetails.expectedTransaction.value)!)",
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
        
        // Send `submitActions` request with
        // actions generated by the intent
        let submitActions = intent.requestToSubmitActions(owner: owner)
        _ = reference.stream?.sendMessage(submitActions)
    }
    
    // MARK: - Status -
    
    func fetchIntentMetadata(owner: KeyPair, intentID: PublicKey, completion: @Sendable @escaping (Result<IntentMetadata, ErrorFetchIntentMetadata>) -> Void) {
        let request = Code_Transaction_V2_GetIntentMetadataRequest.with {
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
    
//    func fetchTransactionLimits(owner: KeyPair, since date: Date, completion: @escaping (Result<Limits, ErrorFetchLimits>) -> Void) {
//        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Date (local): \(date.description(with: .current))")
//        
//        let fetchDate: Date = .now
//        
//        let request = Code_Transaction_V2_GetLimitsRequest.with {
//            $0.owner         = owner.publicKey.codeAccountID
//            $0.consumedSince = .init(date: date)
//            $0.signature     = $0.sign(with: owner)
//        }
//        
//        let call = service.getLimits(request)
//        call.handle(on: queue) { response in
//            
//            let error = ErrorFetchLimits(rawValue: response.result.rawValue) ?? .unknown
//            guard error == .ok else {
//                trace(.failure, components: "Owner: \(owner.publicKey.base58)", "Date (local): \(date.description(with: .current))", "Error: \(error)")
//                completion(.failure(error))
//                return
//            }
//            
//            let limits = Limits(
//                sinceDate: date,
//                fetchDate: fetchDate,
//                sendLimits: response.sendLimitsByCurrency,
//                buyLimits: response.buyModuleLimitsByCurrency,
//                deposits: response.depositLimit
//            )
//            
//            trace(.success, components: "Owner: \(owner.publicKey.base58)", "Date (local): \(date.description(with: .current))", "Max Deposit: \(limits.maxDeposit)")
//            completion(.success(limits))
//            
//        } failure: { error in
//            completion(.failure(.unknown))
//        }
//    }
    
    // MARK: - Withdrawals -
    
    func fetchDestinationMetadata(destination: PublicKey, completion: @Sendable @escaping (Result<DestinationMetadata, Never>) -> Void) {
        trace(.send, components: "Destination: \(destination.base58)")
        
        let request = Code_Transaction_V2_CanWithdrawToAccountRequest.with {
            $0.account = destination.solanaAccountID
        }
        
        let call = service.canWithdrawToAccount(request)
        call.handle(on: queue) { response in
            
            let metadata = DestinationMetadata(
                destination: destination,
                isValid: response.isValidPaymentDestination,
                kind: .init(rawValue: response.accountType.rawValue) ?? .unknown
            )
            
            completion(.success(metadata))
            
        } failure: { _ in
            
            let metadata = DestinationMetadata(
                destination: destination,
                isValid: false,
                kind: .unknown
            )
            
            completion(.success(metadata))
        }
    }
}

// MARK: - Types -

public struct DestinationMetadata {
    
    public let destination: PublicKey
    public let isValid: Bool
    public let kind: Kind
    
    public let hasResolvedDestination: Bool
    public let resolvedDestination: PublicKey
    
    init(destination: PublicKey, isValid: Bool, kind: Kind) {
        self.destination = destination
        self.isValid = isValid
        self.kind = kind
        
        switch kind {
        case .unknown, .token:
            self.hasResolvedDestination = false
            self.resolvedDestination = destination
            
        case .owner:
            self.hasResolvedDestination = true
            self.resolvedDestination = AssociatedTokenAccount(owner: destination, mint: Mint.kin).ata.publicKey
        }
    }
}
            
extension DestinationMetadata {
    public enum Kind: Int {
        case unknown
        case token
        case owner
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
    
    init(error: Code_Transaction_V2_SubmitIntentResponse.Error) {
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

public enum ErrorPaymentHistory: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

public enum ErrorDestinationMetadata: Int, Error {
    case ok
    case notFound
    case unknown = -1
}

public enum ErrorFetchUpgradeableIntets: Int, Error {
    case ok
    case notFound
    case unknown = -1
    case deserializationFailure = -2
}

public enum ErrorAirdrop: Int, Error {
    case ok
    case unavailable
    case alreadyClaimed
    case unknown = -1
}

public enum ErrorDeclareFiatOnramp: Int, Error {
    case ok
    case invalidOwner /// The owner account is not valid (ie. it isn't a Code account)
    case unsupportedCurrency /// The currency isn't supported
    case amountExceedsMaximum /// The amount specified exceeds limits
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Transaction_V2_TransactionClientInterceptorFactoryProtocol {
    func makeDeclareFiatOnrampPurchaseAttemptInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_DeclareFiatOnrampPurchaseAttemptRequest, Code_Transaction_V2_DeclareFiatOnrampPurchaseAttemptResponse>] {
        makeInterceptors()
    }
    
    func makeSwapInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_SwapRequest, Code_Transaction_V2_SwapResponse>] {
        makeInterceptors()
    }
    
    func makeAirdropInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_AirdropRequest, Code_Transaction_V2_AirdropResponse>] {
        makeInterceptors()
    }
    
    func makeCanWithdrawToAccountInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_CanWithdrawToAccountRequest, Code_Transaction_V2_CanWithdrawToAccountResponse>] {
        makeInterceptors()
    }
    
    func makeGetIntentMetadataInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_GetIntentMetadataRequest, Code_Transaction_V2_GetIntentMetadataResponse>] {
        makeInterceptors()
    }
    
//    func makeGetPrioritizedIntentsForPrivacyUpgradeInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_GetPrioritizedIntentsForPrivacyUpgradeRequest, Code_Transaction_V2_GetPrioritizedIntentsForPrivacyUpgradeResponse>] {
//        makeInterceptors()
//    }
    
    func makeGetLimitsInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_GetLimitsRequest, Code_Transaction_V2_GetLimitsResponse>] {
        makeInterceptors()
    }
    
    func makeSubmitIntentInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_SubmitIntentRequest, Code_Transaction_V2_SubmitIntentResponse>] {
        makeInterceptors()
    }
    
//    func makeGetPrivacyUpgradeStatusInterceptors() -> [GRPC.ClientInterceptor<Code_Transaction_V2_GetPrivacyUpgradeStatusRequest, Code_Transaction_V2_GetPrivacyUpgradeStatusResponse>] {
//        makeInterceptors()
//    }
}

// MARK: - GRPCClientType -

extension Code_Transaction_V2_TransactionNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
