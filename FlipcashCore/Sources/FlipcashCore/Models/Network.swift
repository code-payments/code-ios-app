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
    var hostForCore: String {
        switch self {
        case .mainNet:
            return "fc-v2.api.flipcash-infra.net"
        case .testNet:
            return "fc-v2.api.flipcash-infra.net"
        }
    }
    
    var hostForPayments: String {
        switch self {
        case .mainNet:
            return "ocp-v2.api.flipcash-infra.net"
        case .testNet:
            return "ocp-v2.api.flipcash-infra.net"
        }
    }

    var port: Int {
        return 443
    }
}
