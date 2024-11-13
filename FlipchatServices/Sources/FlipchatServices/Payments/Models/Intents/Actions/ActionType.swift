//
//  ActionType.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

protocol ActionType {
    
    var id: Int { get set }
    var serverParameter: ServerParameter? { get set }
    var signer: KeyPair? { get }
    
    static var configCountRequirement: Int { get }
        
    func transactions() throws -> [SolanaTransaction]
    func signatures() throws -> [Signature]
    
    func action() -> Code_Transaction_V2_Action
}

enum ActionTypeError: Error {
    case missingSigner
}

extension ActionType {
    func signatures() throws -> [Signature] {
        guard Self.configCountRequirement > 0 else {
            return []
        }
        
        guard let signer = signer else {
            throw ActionTypeError.missingSigner
        }
        
        return try transactions().map { transaction in
            transaction.signature(using: signer)
        }
    }
}

extension Array where Element == ActionType {
    mutating func numberActions() {
        enumerated().forEach { index, _ in
            self[index].id = index
        }
    }
}
