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
    /// Resolves every host to loopback so nothing built with this network can
    /// reach a real backend. Used by test and preview mocks; transport
    /// construction is unaffected (resolution is lazy), and RPCs fail fast
    /// with a transient transport error, which `TransportClassifiableError`
    /// classifies as `.suppressed`.
    case offline
}

extension Network {
    var hostForCore: String {
        switch self {
        case .mainNet: "fc-v2.api.flipcash-infra.net"
        case .offline: "127.0.0.1"
        }
    }

    var hostForPayments: String {
        switch self {
        case .mainNet: "ocp-v2.api.flipcash-infra.net"
        case .offline: "127.0.0.1"
        }
    }

    var port: Int {
        switch self {
        case .mainNet: 443
        case .offline: 1
        }
    }
}
