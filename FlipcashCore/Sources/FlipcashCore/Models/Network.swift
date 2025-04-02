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
            return "api.flipcash.com"
        case .testNet:
            return "api.flipcash.com"
        }
    }
    
    var hostForPayments: String {
        switch self {
        case .mainNet:
            return "api.flipcash.com"
        case .testNet:
            return "api.flipcash.com"
        }
    }

    var port: Int {
        return 443
    }
}
