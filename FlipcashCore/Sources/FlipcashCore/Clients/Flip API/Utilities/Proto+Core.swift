//
//  Protobuf+Model.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import SwiftProtobuf

// MARK: - Serialize -

extension SwiftProtobuf.Message {
    public func sign(with owner: KeyPair) -> Flipcash_Common_V1_Signature {
        .with { $0.value = owner.sign(try! serializedData()).data }
    }
}

extension KeyPair {
    public func authFor(message: SwiftProtobuf.Message) -> Flipcash_Common_V1_Auth {
        .with {
            $0.keyPair = .with {
                $0.pubKey = self.publicKey.proto
                $0.signature = message.sign(with: self)
            }
        }
    }
}

extension PublicKey {
    public var proto: Flipcash_Common_V1_PublicKey {
        .with { $0.value = data }
    }
}

extension UserID {
    public var proto: Flipcash_Common_V1_UserId {
        .with { $0.value = data }
    }
}
