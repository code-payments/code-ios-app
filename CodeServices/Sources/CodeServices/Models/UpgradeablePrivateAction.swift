//
//  UpgradeablePrivateAction.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public struct UpgradeablePrivateAction: Equatable {
    
    public var id: Int
    public var transactionBlob: Data
    public var clientSignature: Signature
    public var sourceAccountType: AccountType
    public var sourceDerivationIndex: Int
    public var originalDestination: PublicKey
    public var originalAmount: Kin
    public var treasury: PublicKey
    public var recentRoot: Hash
    
    public let transaction: SolanaTransaction
    public let originalNonce: PublicKey
    public let originalCommitment: PublicKey
    public let originalRecentBlockhash: Hash
    
    public init(id: Int, transactionBlob: Data, clientSignature: Signature, sourceAccountType: AccountType, sourceDerivationIndex: Int, originalDestination: PublicKey, originalAmount: Kin, treasury: PublicKey, recentRoot: Hash) throws {
        self.id = id
        self.transactionBlob = transactionBlob
        self.clientSignature = clientSignature
        self.sourceAccountType = sourceAccountType
        self.sourceDerivationIndex = sourceDerivationIndex
        self.originalDestination = originalDestination
        self.originalAmount = originalAmount
        self.treasury = treasury
        self.recentRoot = recentRoot
        
        guard let transaction = SolanaTransaction(data: transactionBlob) else {
            throw Error.failedToParseTransaction
        }
        
        guard let nonceInstruction = transaction.findInstruction(type: SystemProgram.AdvanceNonce.self) else {
            throw Error.missingOriginalNonce
        }
        
        guard let transferInstruction = transaction.findInstruction(type: TimelockProgram.TransferWithAuthority.self) else {
            throw Error.missingOriginalCommitment
        }
        
        self.transaction = transaction
        self.originalNonce = nonceInstruction.nonce
        self.originalCommitment = transferInstruction.destination
        self.originalRecentBlockhash = transaction.recentBlockhash
    }
}

// MARK: - Proto -

extension UpgradeablePrivateAction {
    init(_ proto: Code_Transaction_V2_UpgradeableIntent.UpgradeablePrivateAction) throws {
        guard
            let signature = Signature(proto.clientSignature.value),
            let accountType = AccountType(proto.sourceAccountType, relationship: nil),
            let originalDestination = PublicKey(proto.originalDestination.value),
            let treasury = PublicKey(proto.treasury.value),
            let recentRoot = Hash(proto.recentRoot.value)
        else {
            throw Error.desirializationFailed
        }
        
        try self.init(
            id: Int(proto.actionID),
            transactionBlob: proto.transactionBlob.value,
            clientSignature: signature,
            sourceAccountType: accountType,
            sourceDerivationIndex: Int(proto.sourceDerivationIndex),
            originalDestination: originalDestination,
            originalAmount: Kin(quarks: proto.originalAmount),
            treasury: treasury,
            recentRoot: recentRoot
        )
    }
}

// MARK: - Errors -

extension UpgradeablePrivateAction {
    enum Error: Swift.Error {
        case missingOriginalNonce
        case missingOriginalCommitment
        case failedToParseTransaction
        case desirializationFailed
    }
}
