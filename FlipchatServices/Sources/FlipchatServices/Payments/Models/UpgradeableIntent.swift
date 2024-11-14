//
//  UpgradeableIntent.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

public struct UpgradeableIntent: Equatable, Sendable {
    
    public var id: PublicKey
    public var actions: [UpgradeablePrivateAction]
    
    public init(id: PublicKey, actions: [UpgradeablePrivateAction]) {
        self.id = id
        self.actions = actions
    }
}

// MARK: - Proto -

extension UpgradeableIntent {
    init(_ proto: Code_Transaction_V2_UpgradeableIntent) throws {
        guard
            let intentID = PublicKey(proto.id.value)
        else {
            throw Error.desirializationFailed
        }
        
        let actions = try proto.actions.map {
            try UpgradeablePrivateAction($0)
        }
        
        self.init(
            id: intentID,
            actions: actions
        )
    }
}

// MARK: - Errors -

extension UpgradeableIntent {
    enum Error: Swift.Error {
        case desirializationFailed
    }
}
