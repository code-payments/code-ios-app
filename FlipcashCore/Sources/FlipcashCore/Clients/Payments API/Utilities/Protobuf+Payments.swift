//
//  Protobuf+Model.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

// MARK: - Serialize -

extension SwiftProtobuf.Message {
    public func sign(with owner: KeyPair) -> Ocp_Common_V1_Signature {
        var signature = Ocp_Common_V1_Signature()
        signature.value = owner.sign(try! serializedData()).data
        return signature
    }
}

extension PublicKey {
    public var solanaAccountID: Ocp_Common_V1_SolanaAccountId {
        var accountID = Ocp_Common_V1_SolanaAccountId()
        accountID.value = data
        return accountID
    }
    
    public var codeRendezvousKey: Ocp_Messaging_V1_RendezvousKey {
        var rendezvousKey = Ocp_Messaging_V1_RendezvousKey()
        rendezvousKey.value = data
        return rendezvousKey
    }
    
    public var codeIntentID: Ocp_Common_V1_IntentId {
        var paymentID = Ocp_Common_V1_IntentId()
        paymentID.value = data
        return paymentID
    }
}

extension Signature {
    public var proto: Ocp_Common_V1_Signature {
        var signature = Ocp_Common_V1_Signature()
        signature.value = data
        return signature
    }
}
