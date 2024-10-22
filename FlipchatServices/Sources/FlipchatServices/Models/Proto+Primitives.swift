//
//  Proto+Primitives.swift
//  Flipchat
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeServices
import FlipchatAPI
import SwiftProtobuf

// MARK: - Serialize -

extension KeyPair {
    public var protoAuth: Flipchat_Common_V1_Auth {
        .with {
            $0.keyPair = .with {
                $0.pubKey = self.publicKey.protoPubKey
                $0.signature = $0.sign(with: self)
            }
        }
    }
}

extension SwiftProtobuf.Message {
    public func sign(with owner: KeyPair) -> Flipchat_Common_V1_Signature {
        .with { $0.value = owner.sign(try! serializedData()).data }
    }
}

extension PublicKey {
    public var protoPubKey: Flipchat_Common_V1_PublicKey {
        .with { $0.value = data }
    }
}

extension Signature {
    public var protoSignature: Flipchat_Common_V1_Signature {
        .with { $0.value = data }
    }
}

extension ID {
    public var protoUserID: Flipchat_Common_V1_UserId {
        .with { $0.value = data }
    }
    
    public var protoChatID: Flipchat_Common_V1_ChatId {
        .with { $0.value = data }
    }
}
