//
//  SysVar.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum SysVar: String, CaseIterable {
    case clock             = "SysvarC1ock11111111111111111111111111111111"
    case epochSchedule     = "SysvarEpochSchedu1e111111111111111111111111"
    case fees              = "SysvarFees111111111111111111111111111111111"
    case instructions      = "Sysvar1nstructions1111111111111111111111111"
    case recentBlockhashes = "SysvarRecentB1ockHashes11111111111111111111"
    case rent              = "SysvarRent111111111111111111111111111111111"
    case slotHashes        = "SysvarS1otHashes111111111111111111111111111"
    case slotHistory       = "SysvarS1otHistory11111111111111111111111111"
    case stackHistory      = "SysvarStakeHistory1111111111111111111111111"
}

extension SysVar {
    public var address: PublicKey {
        PublicKey(base58: rawValue)!
    }
    
    public static var addresses: [PublicKey] {
        allCases.map { $0.address }
    }
}
