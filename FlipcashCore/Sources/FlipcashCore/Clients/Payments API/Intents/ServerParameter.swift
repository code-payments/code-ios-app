//
//  ServerParameter.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

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
        case feePayment(PublicKey)
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
                Config(
                    nonce: try PublicKey($0.nonce.value),
                    blockhash: try Hash($0.blockhash.value)
                )
            }
        )
    }
}

extension ServerParameter.Parameter {
    init?(_ proto: Code_Transaction_V2_ServerParameter) throws {
        switch proto.type {
            
        case .feePayment(let param):
            let optionalDestination = try PublicKey(param.destination.value)
            self = .feePayment(optionalDestination)
            
        case .openAccount, .noPrivacyTransfer, .noPrivacyWithdraw, .none:
            return nil
        }
    }
}
