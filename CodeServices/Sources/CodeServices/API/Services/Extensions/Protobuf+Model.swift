//
//  Protobuf+Model.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import SwiftProtobuf

// MARK: - Serialize -

extension SwiftProtobuf.Message {
    func sign(with owner: KeyPair) -> Code_Common_V1_Signature {
        var signature = Code_Common_V1_Signature()
        signature.value = owner.sign(try! serializedData()).data
        return signature
    }
}

extension PublicKey {
    var codeAccountID: Code_Common_V1_SolanaAccountId {
        var accountID = Code_Common_V1_SolanaAccountId()
        accountID.value = data
        return accountID
    }
    
    var codeRendezvousKey: Code_Messaging_V1_RendezvousKey {
        var rendezvousKey = Code_Messaging_V1_RendezvousKey()
        rendezvousKey.value = data
        return rendezvousKey
    }
    
    var codeIntentID: Code_Common_V1_IntentId {
        var paymentID = Code_Common_V1_IntentId()
        paymentID.value = data
        return paymentID
    }
}

extension Signature {
    
    var codeClientSignature: Code_Common_V1_Signature {
        var signature = Code_Common_V1_Signature()
        signature.value = data
        return signature
    }
}

extension ID {
    var codeUserID: Code_Common_V1_UserId {
        var userID = Code_Common_V1_UserId()
        userID.value = data
        return userID
    }
    
    var codeContainerID: Code_Common_V1_DataContainerId {
        var userID = Code_Common_V1_DataContainerId()
        userID.value = data
        return userID
    }
    
    var codeCursor: Code_Transaction_V2_Cursor {
        var cursor = Code_Transaction_V2_Cursor()
        cursor.value = data
        return cursor
    }
}

extension String {
    var codeVerificationCode: Code_Phone_V1_VerificationCode {
        var verificationCode = Code_Phone_V1_VerificationCode()
        verificationCode.value = self
        return verificationCode
    }
}

extension Phone {
    var codePhoneNumber: Code_Common_V1_PhoneNumber {
        var phone = Code_Common_V1_PhoneNumber()
        phone.value = e164
        return phone
    }
}

// MARK: - Deserialize -

extension Phone {
    init?(_ codePhone: Code_Common_V1_PhoneNumber) {
        self.init(codePhone.value)
    }
}

extension User {
    init(codeUser: Code_User_V1_User, containerID: Code_Common_V1_DataContainerId, betaFlagsAllowed: Bool, eligibleAirdrops: [Code_Transaction_V2_AirdropType]) {
        self.init(
            id: .init(data: codeUser.id.value),
            containerID: .init(data: containerID.value),
            phone: Phone(codeUser.view.phoneNumber),
            betaFlagsAllowed: betaFlagsAllowed,
            eligibleAirdrops: eligibleAirdrops.compactMap { AirdropType(rawValue: $0.rawValue) }
        )
    }
}

extension PhoneDescription.RegistraionStatus {
    init(_ codeContactStatus: Code_Contact_V1_ContactStatus) {
        if codeContactStatus.isInviteRevoked {
            self = .revoked
        } else if codeContactStatus.isRegistered {
            self = .registered
        } else if codeContactStatus.isInvited {
            self = .invited
        } else {
            self = .uploaded
        }
    }
}

extension PhoneDescription {
    init?(_ codeContact: Code_Contact_V1_Contact) {
        guard let phone = Phone(codeContact.phoneNumber) else {
            return nil
        }
        
        self.init(
            phone: phone,
            status: RegistraionStatus(codeContact.status)
        )
    }
}

extension AccountType {
    var accountType: Code_Common_V1_AccountType {
        switch self {
        case .primary:
            return .primary
            
        case .incoming:
            return .temporaryIncoming
            
        case .outgoing:
            return .temporaryOutgoing
            
        case .bucket(let type):
            switch type {
            case .bucket1:    return .bucket1Kin
            case .bucket10:   return .bucket10Kin
            case .bucket100:  return .bucket100Kin
            case .bucket1k:   return .bucket1000Kin
            case .bucket10k:  return .bucket10000Kin
            case .bucket100k: return .bucket100000Kin
            case .bucket1m:   return .bucket1000000Kin
            }
            
        case .remoteSend:
            return .remoteSendGiftCard
        case .relationship:
            return .relationship
        }
    }
    
    init?(_ accountType: Code_Common_V1_AccountType, relationship: Code_Common_V1_Relationship?) {
        switch accountType {
        case .primary:
            self = .primary
        case .legacyPrimary2022:
            self = .primary
        case .temporaryIncoming:
            self = .incoming
        case .temporaryOutgoing:
            self = .outgoing
        case .bucket1Kin:
            self = .bucket(.bucket1)
        case .bucket10Kin:
            self = .bucket(.bucket10)
        case .bucket100Kin:
            self = .bucket(.bucket100)
        case .bucket1000Kin:
            self = .bucket(.bucket1k)
        case .bucket10000Kin:
            self = .bucket(.bucket10k)
        case .bucket100000Kin:
            self = .bucket(.bucket100k)
        case .bucket1000000Kin:
            self = .bucket(.bucket1m)
        case .remoteSendGiftCard:
            self = .remoteSend
        case .relationship:
            guard let relationship else {
                return nil
            }
            
            guard let domain = Domain(relationship.domain.value) else {
                return nil
            }
            
            self = .relationship(domain)
            
        case .associatedTokenAccount:
            return nil
        case .unknown:
            return nil
        case .UNRECOGNIZED:
            return nil
        }
    }
}

extension AccountInfo {
    init?(_ info: Code_Account_V1_TokenAccountInfo) {
        guard
            let accountType = AccountType(info.accountType, relationship: info.relationship),
            let address = PublicKey(info.address.value),
            let balanceSource = BalanceSource(info.balanceSource),
            let managementState = ManagementState(info.managementState),
            let blockchainState = BlockchainState(info.blockchainState),
            let claimState = ClaimState(info.claimState)
        else {
            return nil
        }
        
        let owner = PublicKey(info.owner.value)
        let authority = PublicKey(info.authority.value)
        
        let originalKinAmount: KinAmount?
        
        if let originalCurrency = CurrencyCode(currencyCode: info.originalExchangeData.currency) {
            originalKinAmount = KinAmount(
                kin: Kin(quarks: info.originalExchangeData.quarks),
                rate: Rate(
                    fx: Decimal(info.originalExchangeData.exchangeRate),
                    currency: originalCurrency
                )
            )
        } else {
            originalKinAmount = nil
        }
        
        let relationship = Relationship(domain: info.relationship.domain.value)
        
        self.init(
            index: Int(info.index),
            accountType: accountType,
            address: address,
            owner: owner,
            authority: authority,
            balanceSource: balanceSource,
            balance: Kin(quarks: info.balance),
            managementState: managementState,
            blockchainState: blockchainState,
            claimState: claimState,
            mustRotate: info.mustRotate,
            originalKinAmount: originalKinAmount,
            relationship: relationship
        )
    }
}

extension AccountInfo.BalanceSource {
    init?(_ source: Code_Account_V1_TokenAccountInfo.BalanceSource) {
        switch source {
        case .unknown:
            self = .unknown
        case .blockchain:
            self = .blockchain
        case .cache:
            self = .cache
        case .UNRECOGNIZED:
            return nil
        }
    }
}

extension AccountInfo.ManagementState {
    init?(_ state: Code_Account_V1_TokenAccountInfo.ManagementState) {
        switch state {
        case .unknown:
            self = .unknown
        case .none:
            self = .none
        case .locking:
            self = .locking
        case .locked:
            self = .locked
        case .unlocking:
            self = .unlocking
        case .unlocked:
            self = .unlocked
        case .closing:
            self = .closing
        case .closed:
            self = .closed
        case .UNRECOGNIZED:
            return nil
        }
    }
}

extension AccountInfo.BlockchainState {
    init?(_ state: Code_Account_V1_TokenAccountInfo.BlockchainState) {
        switch state {
        case .unknown:
            self = .unknown
        case .doesNotExist:
            self = .doesntExist
        case .exists:
            self = .exists
        case .UNRECOGNIZED:
            return nil
        }
    }
}

extension AccountInfo.ClaimState {
    init?(_ state: Code_Account_V1_TokenAccountInfo.ClaimState) {
        switch state {
        case .unknown:
            self = .unknown
        case .notClaimed:
            self = .notClaimed
        case .claimed:
            self = .claimed
        case .expired:
            self = .expired
        case .UNRECOGNIZED:
            return nil
        }
    }
}

extension IntentMetadata {
    init?(_ metadata: Code_Transaction_V2_Metadata) {
        guard let type = metadata.type else {
            return nil
        }
        
        switch type {
        case .openAccounts:
            self = .openAccounts
            
        case .receivePaymentsPrivately:
            self = .receivePaymentsPrivately
            
        case .receivePaymentsPublicly(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .receivePaymentsPublicly(metadata)
            
        case .upgradePrivacy:
            self = .upgradePrivacy
            
        case .migrateToPrivacy2022:
            self = .migrateToPrivacy2022
            
        case .sendPrivatePayment(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .sendPrivatePayment(metadata)
            
        case .sendPublicPayment(let meta):
            guard let metadata = Self.paymentMetadata(for: meta.exchangeData) else {
                return nil
            }
            
            self = .sendPublicPayment(metadata)
            
        case .establishRelationship:
            // TODO: Create relevant metadata
            return nil
        }
    }
    
    private static func paymentMetadata(for exchangeData: Code_Transaction_V2_ExchangeData) -> PaymentMetadata? {
        guard let currency = CurrencyCode(currencyCode: exchangeData.currency) else {
            return nil
        }
        
        return PaymentMetadata(
            amount: KinAmount(
                kin: Kin(quarks: exchangeData.quarks),
                rate: Rate(
                    fx: Decimal(exchangeData.exchangeRate),
                    currency: currency
                )
            )
        )
    }
}

extension Limits {
    init(sinceDate: Date, fetchDate: Date, limits: [String: Code_Transaction_V2_RemainingSendLimit], deposits: Code_Transaction_V2_DepositLimit) {
        let dictionary = limits.mapValues { Decimal(Double($0.nextTransaction)) }
        var container: [CurrencyCode: Decimal] = [:]
        dictionary.forEach { code, limit in
            if let currency = CurrencyCode(currencyCode: code) {
                container[currency] = limit
            }
        }
        
        self.init(
            sinceDate: sinceDate,
            fetchDate: fetchDate,
            map: container,
            maxDeposit: Kin(quarks: deposits.maxQuarks)
        )
    }
}
