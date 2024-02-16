//
//  ServerParameter.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ServerParameter {
    
    let actionID: Int
    let parameter: Parameter?
    let configs: [Config]
    
    init(actionID: Int, parameter: Parameter?, configs: [Config]) {
        self.actionID  = actionID
        self.parameter = parameter
        self.configs   = configs
    }
}

// MARK: - Config -

extension ServerParameter {
    struct Config {
        
        let nonce: PublicKey
        let blockhash: Hash
        
        init(nonce: PublicKey, blockhash: Hash) {
            self.nonce = nonce
            self.blockhash = blockhash
        }
    }
}

// MARK: - Parameter Types -

extension ServerParameter {
    enum Parameter {
        case tempPrivacy(TempPrivacy)
        case permanentPrivacyUpgrade(PermanentPrivacyUpgrade)
        case feePayment(PublicKey?)
    }
}

extension ServerParameter {
    struct TempPrivacy {
        
        let treasury: PublicKey
        let recentRoot: Hash
        
        init(treasury: PublicKey, recentRoot: Hash) {
            self.treasury = treasury
            self.recentRoot = recentRoot
        }
    }
}

extension ServerParameter {
    struct PermanentPrivacyUpgrade {
        
        let newCommitment: PublicKey
        let newCommitmentTranscript: Hash
        let newCommitmentDestination: PublicKey
        let newCommitmentAmount: Kin
        let merkleRoot: Hash
        let merkleProof: [Hash]
        
        init(newCommitment: PublicKey, newCommitmentTranscript: Hash, newCommitmentDestination: PublicKey, newCommitmentAmount: Kin, merkleRoot: Hash, merkleProof: [Hash]) {
            self.newCommitment = newCommitment
            self.newCommitmentTranscript = newCommitmentTranscript
            self.newCommitmentDestination = newCommitmentDestination
            self.newCommitmentAmount = newCommitmentAmount
            self.merkleRoot = merkleRoot
            self.merkleProof = merkleProof
        }
    }
}

// MARK: - Error -

extension ServerParameter {
    enum Error: Swift.Error {
        case deserializationFailed
    }
}

extension ServerParameter.Parameter {
    enum Error: Swift.Error {
        case deserializationFailed
    }
}

// MARK: - Proto -

extension ServerParameter {
    init(_ proto: Code_Transaction_V2_ServerParameter) throws {
        self.init(
            actionID: Int(proto.actionID),
            parameter: try Parameter(proto),
            configs: try proto.nonces.map {
                guard
                    let nonce = PublicKey($0.nonce.value),
                    let blockhash = Hash($0.blockhash.value)
                else {
                    throw Error.deserializationFailed
                }
                
                return Config(
                    nonce: nonce,
                    blockhash: blockhash
                )
            }
        )
    }
}

extension ServerParameter.Parameter {
    init?(_ proto: Code_Transaction_V2_ServerParameter) throws {
        switch proto.type {
            
        case .temporaryPrivacyTransfer(let param):
            guard
                let treasury = PublicKey(param.treasury.value),
                let recentRoot = Hash(param.recentRoot.value)
            else {
                throw Error.deserializationFailed
            }
            
            self = .tempPrivacy(
                .init(
                    treasury: treasury,
                    recentRoot: recentRoot
                )
            )
            
        case .temporaryPrivacyExchange(let param):
            guard
                let treasury = PublicKey(param.treasury.value),
                let recentRoot = Hash(param.recentRoot.value)
            else {
                throw Error.deserializationFailed
            }
            
            self = .tempPrivacy(
                .init(
                    treasury: treasury,
                    recentRoot: recentRoot
                )
            )
            
        case .permanentPrivacyUpgrade(let param):
            guard
                let newCommitment = PublicKey(param.newCommitment.value),
                let newCommitmentTranscript = Hash(param.newCommitmentTranscript.value),
                let newCommitmentDestination = PublicKey(param.newCommitmentDestination.value),
                let merkleRoot = Hash(param.merkleRoot.value)
            else {
                throw Error.deserializationFailed
            }
            
            let merkleProof = try param.merkleProof.map {
                guard let hash = Hash($0.value) else {
                    throw Error.deserializationFailed
                }
                return hash
            }
            
            self = .permanentPrivacyUpgrade(
                .init(
                    newCommitment: newCommitment,
                    newCommitmentTranscript: newCommitmentTranscript,
                    newCommitmentDestination: newCommitmentDestination,
                    newCommitmentAmount: Kin(quarks: param.newCommitmentAmount),
                    merkleRoot: merkleRoot,
                    merkleProof: merkleProof
                )
            )
            
        case .feePayment(let param):
            // PublicKey will be `nil` for .thirdParty fee payments
            let optionalDestination = PublicKey(param.codeDestination.value)
            self = .feePayment(optionalDestination)
            
        case .openAccount, .closeEmptyAccount, .closeDormantAccount, .noPrivacyTransfer, .noPrivacyWithdraw, .none:
            return nil
        }
    }
}
