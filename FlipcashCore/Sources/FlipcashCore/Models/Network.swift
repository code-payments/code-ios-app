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
}

extension Network {
    var hostForCore: String {
        return "fc-v2.api.flipcash-infra.net"
    }

    var hostForPayments: String {
        return "ocp-v2.api.flipcash-infra.net"
    }

    var port: Int {
        return 443
    }
}
