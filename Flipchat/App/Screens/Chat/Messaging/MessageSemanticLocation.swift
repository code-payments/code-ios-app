//
//  MessageSemanticLocation.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public enum MessageSemanticLocation {
    
    case standalone
    case beginning
    case middle
    case end
    
    static func forIndex(_ index: Int, count: Int) -> MessageSemanticLocation {
        if count < 2 {
            return .standalone
        }
        
        if index == 0 {
            return .beginning
        } else if index >= count - 1 {
            return .end
        } else {
            return .middle
        }
    }
    
    var topLeftRadius: CGFloat {
        Metrics.chatMessageRadiusSmall
    }
    
    var bottomLeftRadius: CGFloat {
        switch self {
        case .standalone, .end:
            Metrics.chatMessageRadiusLarge
        case .middle, .beginning:
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var topRightRadius: CGFloat {
        switch self {
        case .standalone, .beginning:
            Metrics.chatMessageRadiusLarge
        case .middle, .end:
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var bottomRightRadius: CGFloat {
        switch self {
        case .standalone, .end:
            Metrics.chatMessageRadiusLarge
        case .middle, .beginning:
            Metrics.chatMessageRadiusSmall
        }
    }
}
