//
//  ButtonState.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum ButtonState: Equatable {
    
    case normal
    case loading
    case success
    case successText(String)
    
    public var isNormal: Bool {
        switch self {
        case .normal:
            return true
        default:
            return false
        }
    }
}
