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
            switch self {
            case .standalone, .beginning:
                Metrics.chatMessageRadiusLarge
            case .middle, .end:
                Metrics.chatMessageRadiusSmall
            }
        }
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
        if received {
            switch self {
            case .standalone, .beginning:
                Metrics.chatMessageRadiusLarge
            case .middle, .end:
                Metrics.chatMessageRadiusSmall
            }
        } else {
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
