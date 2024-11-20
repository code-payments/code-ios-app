//
//  MessageSemanticLocation.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public enum MessageSemanticLocation: Equatable, Hashable {
    
    case standalone(Direction)
    case beginning(Direction)
    case middle(Direction)
    case end(Direction)
    
    var isFirst: Bool {
        switch self {
        case .standalone, .beginning:
            return true
        case .middle, .end:
            return false
        }
    }
    
    var isBottomHalf: Bool {
        switch self {
        case .middle, .end:
            return true
        case .beginning, .standalone:
            return false
        }
    }
    
    var received: Bool {
        switch self {
        case .standalone(let direction):
            return direction == .received
        case .beginning(let direction):
            return direction == .received
        case .middle(let direction):
            return direction == .received
        case .end(let direction):
            return direction == .received
        }
    }
    
    var topLeftRadius: CGFloat {
        if received {
            Metrics.chatMessageRadiusSmall
        } else {
            Metrics.chatMessageRadiusLarge
        }
    }
    
    var bottomLeftRadius: CGFloat {
        if received {
            switch self {
            case .end, .standalone:
                Metrics.chatMessageRadiusLarge
            case .middle, .beginning:
                Metrics.chatMessageRadiusSmall
            }
        } else {
            Metrics.chatMessageRadiusLarge
        }
    }
    
    var topRightRadius: CGFloat {
        if received {
            Metrics.chatMessageRadiusLarge
        } else {
            Metrics.chatMessageRadiusSmall
        }
    }
    
    var bottomRightRadius: CGFloat {
        if received {
            Metrics.chatMessageRadiusLarge
        } else {
            switch self {
            case .end, .standalone:
                Metrics.chatMessageRadiusLarge
            case .middle, .beginning:
                Metrics.chatMessageRadiusSmall
            }
        }
    }
}

extension MessageSemanticLocation {
    public enum Direction: Equatable, Hashable {
        case received
        case sent
        
        init(received: Bool) {
            if received {
                self = .received
            } else {
                self = .sent
            }
        }
    }
}
