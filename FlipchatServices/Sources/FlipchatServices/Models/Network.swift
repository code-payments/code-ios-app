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
            return "api.flipchat.codeinfra.net"
        case .testNet:
            return "api.flipchat.codeinfra.net"
        }
    }

    var port: Int {
        return 443
    }
}
