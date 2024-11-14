//
//  Network.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum Network {
    case mainNet
    case testNet
}

extension Network {
    var host: String {
        switch self {
        case .mainNet:
            return "chat.api.flipchat-infra.xyz"
        case .testNet:
            return "chat.api.flipchat-infra.xyz"
        }
    }
    
    var paymentsHost: String {
        switch self {
        case .mainNet:
            return "payments.api.flipchat-infra.xyz"
        case .testNet:
            return "payments.api.flipchat-infra.xyz"
        }
    }

    var port: Int {
        return 443
    }
}
