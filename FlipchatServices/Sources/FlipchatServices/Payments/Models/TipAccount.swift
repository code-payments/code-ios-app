//
//  TipAccount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

public enum TipAccount {
    
    case x(String)
    
    public var platform: String {
        switch self {
        case .x: return "X"
        }
    }
    
    public var username: String {
        switch self {
        case .x(let u): return u
        }
    }
}

extension TipAccount {
    var codePlatform: Code_Transaction_V2_TippedUser.Platform {
        switch self {
        case .x: return .twitter
        }
    }
}
