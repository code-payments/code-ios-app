//
//  IntentType.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

protocol IntentType: AnyObject {
    
    var id: PublicKey { get }
    var actionGroup: ActionGroup { get set }
    
    func signatures() throws -> [Signature]
    
    func metadata() -> Code_Transaction_V2_Metadata
}

extension IntentType {
    var actions: [ActionType] {
        actionGroup.actions
    }
    
    func signatures() throws -> [Signature] {
        try actions.flatMap { try $0.signatures() }
    }
    
    func apply(parameters: [ServerParameter]) throws {
        guard parameters.count == actions.count else {
            throw IntentError.invalidParameterCount
        }
        
        parameters.enumerated().forEach { index, parameter in
            actionGroup.actions[index].serverParameter = parameter
        }
    }
}

// MARK: - Errors -

enum IntentError: Swift.Error {
    case invalidParameterCount
    case actionParameterMismatch
}

// MARK: - Proto -

extension IntentType {
    func requestToSubmitSignatures() throws -> Code_Transaction_V2_SubmitIntentRequest {
        let signatures = try signatures().map { $0.proto }
        return .with {
            $0.submitSignatures = .with {
                $0.signatures = signatures
            }
        }
    }
}

extension IntentType {
    func requestToSubmitActions(owner: KeyPair) -> Code_Transaction_V2_SubmitIntentRequest {
        .with {
            $0.submitActions = .with {
                $0.owner = owner.publicKey.solanaAccountID
                $0.id = id.codeIntentID
                $0.metadata = metadata()
                $0.actions = actions.map { $0.action() }
                $0.signature = $0.sign(with: owner)
            }
        }
    }
}

struct ActionGroup {
    
    var actions: [ActionType] {
        didSet {
            actions.numberActions()
        }
    }
    
    init() {
        self.init(actions: [])
    }
    
    init(actions: [ActionType]) {
        self.actions = actions
        self.actions.numberActions()
    }
    
    mutating func append(_ actionType: ActionType) {
        actions.append(actionType)
    }
    
    mutating func append(contentsOf actionTypes: [ActionType]) {
        actions.append(contentsOf: actionTypes)
    }
}

extension ActionGroup: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        debugDescription
    }
    
    var debugDescription: String {
        actions.map { action in
            if let transfer = action as? ActionTransfer {
                return "\(transfer.amount) -> \(transfer.destination.base58) (\(transfer.kind))"
                
            } else {
                return "Unknown action"
            }
            
        }.joined(separator: "\n")
    }
    
    func prettyPrinted() {
        debugDescription.components(separatedBy: .newlines).forEach {
            print($0)
        }
    }
}
