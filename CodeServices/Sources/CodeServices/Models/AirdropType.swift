//
//  AirdropType.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

public enum AirdropType: Int, Codable, Equatable {
    case unknown
    case giveFirstKin
    case getFirstKin
}

// MARK: - Proto -

extension AirdropType {
    
    init?(_ grpcType: Code_Transaction_V2_AirdropType) {
        switch grpcType {
        case .unknown:
            self = .unknown
        case .giveFirstKin:
            self = .giveFirstKin
        case .getFirstKin:
            self = .getFirstKin
        default:
            return nil
        }
    }
    
    var grpcType: Code_Transaction_V2_AirdropType {
        switch self {
        case .unknown:
            return .unknown
        case .giveFirstKin:
            return .giveFirstKin
        case .getFirstKin:
            return .getFirstKin
        }
    }
}
