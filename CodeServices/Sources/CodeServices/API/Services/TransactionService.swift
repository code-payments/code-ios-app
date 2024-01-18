//
//  TransactionService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC
import NIO
import DeviceCheck

class TransactionService: CodeService<Code_Transaction_V2_TransactionNIOClient> {
    
    typealias BidirectionalStream = BidirectionalStreamReference<Code_Transaction_V2_SubmitIntentRequest, Code_Transaction_V2_SubmitIntentResponse>
    
    // MARK: - Account Creation -
    
    func createAccounts(with organizer: Organizer, completion: @escaping (Result<IntentCreateAccounts, Error>) -> Void) {
        trace(.send)
        
        let intent = IntentCreateAccounts(
            organizer: organizer
        )
        
        let device = DCDevice.current
        if device.isSupported {
            device.generateToken { token, error in
                trace(.warning, components: "Device token: \(token?.base64EncodedString() ?? "n/a")")
                self.submit(
                    intent: intent,
                    owner: organizer.tray.owner.cluster.authority.keyPair,
                    deviceToken: token
                ) { result in
                    switch result {
                    case .success(let intent):
                        trace(.success)
                        completion(.success(intent))
                        
                    case .failure(let error):
                        trace(.failure, components: "Error: \(error)")
                        completion(.failure(error))
                    }
                }
            }
            
        } else {
            completion(.failure(ErrorSubmitIntent.deviceTokenUnavailable))
        }
    }
    
    // MARK: - Transfer -
    
    func transfer(amount: KinAmount, fee: Kin = 0, organizer: Organizer, rendezvous: PublicKey, destination: PublicKey, isWithdrawal: Bool, completion: @escaping (Result<IntentPrivateTransfer, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentPrivateTransfer(
                rendezvous: rendezvous,
                organizer: organizer,
                destination: destination,
                amount: amount,
                fee: fee,
                isWithdrawal: isWithdrawal
            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    func receiveFromIncoming(amount: Kin, organizer: Organizer, completion: @escaping (Result<IntentReceive, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentReceive(
                organizer: organizer,
                amount: amount
            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    func receiveFromPrimary(amount: Kin, organizer: Organizer, completion: @escaping (Result<IntentDeposit, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentDeposit(
                source: .primary,
                organizer: organizer,
                amount: amount
            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    func receiveFromRelationship(domain: Domain, amount: Kin, organizer: Organizer, completion: @escaping (Result<IntentPublicTransfer, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentPublicTransfer(
                organizer: organizer,
                source: .relationship(domain),
                destination: organizer.primaryVault,
                amount: KinAmount(kin: amount, rate: .oneToOne)
            )
//            let intent = try IntentDeposit(
//                source: .relationship(domain),
//                organizer: organizer,
//                amount: amount
//            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    func withdraw(amount: KinAmount, organizer: Organizer, destination: PublicKey, completion: @escaping (Result<IntentPublicTransfer, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentPublicTransfer(
                organizer: organizer,
                source: .primary,
                destination: destination,
                amount: amount
            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    func upgradePrivacy(mnemonic: MnemonicPhrase, upgradeableIntent: UpgradeableIntent, completion: @escaping (Result<IntentUpgradePrivacy, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentUpgradePrivacy(mnemonic: mnemonic, upgradeableIntent: upgradeableIntent)
            
            submit(intent: intent, owner: mnemonic.solanaKeyPair()) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Remote Send -
    
    func sendRemotely(amount: KinAmount, organizer: Organizer, rendezvous: PublicKey, giftCard: GiftCardAccount, completion: @escaping (Result<IntentRemoteSend, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentRemoteSend(
                rendezvous: rendezvous,
                organizer: organizer,
                giftCard: giftCard,
                amount: amount
            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    func receiveRemotely(amount: Kin, organizer: Organizer, giftCard: GiftCardAccount, isVoiding: Bool, completion: @escaping (Result<IntentRemoteReceive, Error>) -> Void) {
        trace(.send)
        
        do {
            let intent = try IntentRemoteReceive(
                organizer: organizer,
                giftCard: giftCard,
                amount: amount,
                isVoidingGiftCard: isVoiding
            )
            
            submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
                switch result {
                case .success(let intent):
                    trace(.success)
                    completion(.success(intent))
                    
                case .failure(let error):
                    trace(.failure, components: "Error: \(error)")
                    completion(.failure(error))
                }
            }
            
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Relationship -
    
    func establishRelationship(organizer: Organizer, domain: Domain, completion: @escaping (Result<IntentEstablishRelationship, Error>) -> Void) {
        trace(.send, components: "Domain: \(domain.urlString)", "Host: \(domain.relationshipHost)")
        
        let intent = IntentEstablishRelationship(
            organizer: organizer,
            domain: domain
        )
        
        submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
            switch result {
            case .success(let intent):
                trace(.success, components: "Domain: \(domain.urlString)", "Host: \(domain.relationshipHost)")
                completion(.success(intent))
                
            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - AirDrop -
    
    func airdrop(type: AirdropType, owner: KeyPair, completion: @escaping (Result<PaymentMetadata, ErrorAirdrop>) -> Void) {
        trace(.send)
        
        let request = Code_Transaction_V2_AirdropRequest.with {
            $0.airdropType = type.grpcType
            $0.owner = owner.publicKey.codeAccountID
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
            
            guard let currency = CurrencyCode(currencyCode: response.exchangeData.currency) else {
                trace(.failure, components: "Failed to parse currency.")
                completion(.failure(.unknown))
                return
            }
            
            let amount = KinAmount(
                kin: Kin(quarks: response.exchangeData.quarks),
                rate: Rate(
                    fx: Decimal(response.exchangeData.exchangeRate),
                    currency: currency
                )
            )
            
            let metadata = PaymentMetadata(amount: amount)
            
            trace(.success, components: "Received: \(amount.kin.formattedFiat(rate: amount.rate, suffix: nil))")
            completion(.success(metadata))
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Migration -
    
    func migrateToPrivacy(amount: Kin, organizer: Organizer, completion: @escaping (Result<IntentMigratePrivacy, Error>) -> Void) {
        trace(.send)
        
        let intent = IntentMigratePrivacy(
            organizer: organizer,
            amount: amount
        )
        
        submit(intent: intent, owner: organizer.tray.owner.cluster.authority.keyPair) { result in
            switch result {
            case .success(let intent):
                trace(.success)
                completion(.success(intent))
                
            case .failure(let error):
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Submit -
    
    private func submit<T>(intent: T, owner: KeyPair, deviceToken: Data? = nil, completion: @escaping (Result<T, ErrorSubmitIntent>) -> Void) where T: IntentType {
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
                let intentError = ErrorSubmitIntent(rawValue: error.code.rawValue) ?? .unknown
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
            trace(.warning, components: "Stream closed: \(result)")
            
            // We release the stream reference after the stream has been
            // closed and there's no further actions required
            reference.release()
        }
        
        // Send `submitActions` request with
        // actions generated by the intent
        let submitActions = intent.requestToSubmitActions(owner: owner, deviceToken: deviceToken)
        _ = reference.stream?.sendMessage(submitActions)
    }
    
    // MARK: - Status -
    
    func fetchIntentMetadata(owner: KeyPair, intentID: PublicKey, completion: @escaping (Result<IntentMetadata, ErrorFetchIntentMetadata>) -> Void) {
        let request = Code_Transaction_V2_GetIntentMetadataRequest.with {
            $0.intentID  = intentID.codeIntentID
            $0.owner     = owner.publicKey.codeAccountID
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getIntentMetadata(request)
        call.handle(on: queue) { response in
            
            let result = ErrorFetchIntentMetadata(rawValue: response.result.rawValue) ?? .unknown
            guard result == .ok else {
                completion(.failure(result))
                return
            }
            
            guard let metadata = IntentMetadata(response.metadata) else {
                trace(.failure, components: "Failed to parse metadata: \(response.metadata)")
                completion(.failure(.failedToParse))
                return
            }
            
            trace(.success, components: "Intent Successful: \(intentID.base58)")
            completion(.success(metadata))
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Limits -
    
    func fetchTransactionLimits(owner: KeyPair, since date: Date, completion: @escaping (Result<Limits, ErrorFetchLimits>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Date (local): \(date.description(with: .current))")
        
        let fetchDate: Date = .now()
        
        let request = Code_Transaction_V2_GetLimitsRequest.with {
            $0.owner         = owner.publicKey.codeAccountID
            $0.consumedSince = .init(date: date)
            $0.signature     = $0.sign(with: owner)
        }
        
        let call = service.getLimits(request)
        call.handle(on: queue) { response in
            
            let error = ErrorFetchLimits(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                trace(.failure, components: "Owner: \(owner.publicKey.base58)", "Date (local): \(date.description(with: .current))", "Error: \(error)")
                completion(.failure(error))
                return
            }
            
            let limits = Limits(
                sinceDate: date,
                fetchDate: fetchDate,
                limits: response.remainingSendLimitsByCurrency,
                deposits: response.depositLimit
            )
            
            trace(.success, components: "Owner: \(owner.publicKey.base58)", "Date (local): \(date.description(with: .current))", "Max Deposit: \(limits.maxDeposit)")
            completion(.success(limits))
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - History -
    
    func fetchPaymentHistory(owner: KeyPair, after id: ID? = nil, pageSize: Int, completion: @escaping (Result<[HistoricalTransaction], ErrorPaymentHistory>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)", "Cursor: \(id ?? .null)")
        
        let request = Code_Transaction_V2_GetPaymentHistoryRequest.with {
            $0.owner     = owner.publicKey.codeAccountID
            $0.direction = .asc
            $0.pageSize  = UInt32(pageSize)
            
            if let id = id {
                $0.cursor = id.codeCursor
            }
            
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getPaymentHistory(request)
        call.handle(on: queue) { response in
            trace(.success, components: "Fetched \(response.items.count) historical payments.")
            let error = ErrorPaymentHistory(rawValue: response.result.rawValue) ?? .unknown
            switch error {
            case .ok:
                let transactions = response.items.compactMap { HistoricalTransaction($0) }
                completion(.success(transactions))
                
            case .notFound:
                completion(.success([]))
                
            case .unknown:
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    // MARK: - Withdrawals -
    
    func fetchDestinationMetadata(destination: PublicKey, completion: @escaping (Result<DestinationMetadata, Never>) -> Void) {
        trace(.send, components: "Destination: \(destination.base58)")
        
        let request = Code_Transaction_V2_CanWithdrawToAccountRequest.with {
            $0.account = destination.codeAccountID
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
    
    // MARK: - Privacy Upgrade -
    
    func fetchUpgradeableIntents(owner: KeyPair, completion: @escaping (Result<[UpgradeableIntent], ErrorFetchUpgradeableIntets>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        let request = Code_Transaction_V2_GetPrioritizedIntentsForPrivacyUpgradeRequest.with {
            $0.owner = owner.publicKey.codeAccountID
            $0.limit = 100 // TODO: Page until the end
            $0.signature = $0.sign(with: owner)
        }
        
        let call = service.getPrioritizedIntentsForPrivacyUpgrade(request)
        call.handle(on: queue) { response in
            
            let result = ErrorFetchUpgradeableIntets(rawValue: response.result.rawValue) ?? .unknown
            switch result {
            case .ok:
                do {
                    let upgradeableIntents = try response.items.map {
                        try UpgradeableIntent($0)
                    }
                    trace(.success, components: "Fetched \(upgradeableIntents.count) upgradeable intents")
                    completion(.success(upgradeableIntents))
                    
                } catch {
                    trace(.failure, components: "Upgradeable intents available but deserialization failed")
                    completion(.failure(.deserializationFailure))
                }
                
            case .notFound:
                trace(.success, components: "No upgradeable intents")
                completion(.success([]))
                
            case .unknown, .deserializationFailure:
                completion(.failure(result))
            }
            
        } failure: { _ in
            completion(.failure(.unknown))
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
            self.resolvedDestination = AssociatedTokenAccount(owner: destination).ata.publicKey
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

public enum ErrorSubmitIntent: Int, Error {
    /// Denied by a guard (spam, money laundering, etc)
    case denied
    /// The intent is invalid.
    case invalidIntent
    /// There is an issue with provided signatures.
    case signatureError
    /// Server detected client has stale state.
    case staleState
    /// Unknown reason
    case unknown = -1
    /// Device token unavailable
    case deviceTokenUnavailable = -2
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

// MARK: - Interceptors -

extension InterceptorFactory: Code_Transaction_V2_TransactionClientInterceptorFactoryProtocol {
    func makeAirdropInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_AirdropRequest, CodeAPI.Code_Transaction_V2_AirdropResponse>] {
        makeInterceptors()
    }
    
    func makeCanWithdrawToAccountInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_CanWithdrawToAccountRequest, CodeAPI.Code_Transaction_V2_CanWithdrawToAccountResponse>] {
        makeInterceptors()
    }
    
    func makeGetIntentMetadataInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_GetIntentMetadataRequest, CodeAPI.Code_Transaction_V2_GetIntentMetadataResponse>] {
        makeInterceptors()
    }
    
    func makeGetPrioritizedIntentsForPrivacyUpgradeInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_GetPrioritizedIntentsForPrivacyUpgradeRequest, CodeAPI.Code_Transaction_V2_GetPrioritizedIntentsForPrivacyUpgradeResponse>] {
        makeInterceptors()
    }
    
    func makeGetLimitsInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_GetLimitsRequest, CodeAPI.Code_Transaction_V2_GetLimitsResponse>] {
        makeInterceptors()
    }
    
    func makeGetPaymentHistoryInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_GetPaymentHistoryRequest, CodeAPI.Code_Transaction_V2_GetPaymentHistoryResponse>] {
        makeInterceptors()
    }
    
    func makeSubmitIntentInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_SubmitIntentRequest, CodeAPI.Code_Transaction_V2_SubmitIntentResponse>] {
        makeInterceptors()
    }
    
    func makeGetPrivacyUpgradeStatusInterceptors() -> [GRPC.ClientInterceptor<CodeAPI.Code_Transaction_V2_GetPrivacyUpgradeStatusRequest, CodeAPI.Code_Transaction_V2_GetPrivacyUpgradeStatusResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Transaction_V2_TransactionNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
