//
//  DialogAction.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

public struct DialogAction {
    
    public let kind: Kind
    public let title: String
    public let action: () -> Void
    
    init(kind: Kind, title: String, action: @escaping () -> Void) {
        self.kind   = kind
        self.title  = title
        self.action = action
    }
    
    public static func standard(_ title: String, action: @escaping () -> Void) -> Self {
        self.init(
            kind: .standard,
            title: title,
            action: action
        )
    }
    
    public static func subtle(_ title: String, action: @escaping () -> Void) -> Self {
        self.init(
            kind: .subtle,
            title: title,
            action: action
        )
    }
    
    public static func destructive(_ title: String, action: @escaping () -> Void) -> Self {
        self.init(
            kind: .destructive,
            title: title,
            action: action
        )
    }
    
    // MARK: - Pre-baked -
    
    public static func okay(action: @escaping () -> Void) -> Self {
        self.init(
            kind: .standard,
            title: "OK",
            action: action
        )
    }
    
    public static func cancel(action: @escaping () -> Void) -> Self {
        self.init(
            kind: .subtle,
            title: "Cancel",
            action: action
        )
    }
}

// MARK: - Kind -

extension DialogAction {
    public enum Kind {
        case standard
        case subtle
        case destructive
        
        var buttonStyle: CodeButton.Style {
            switch self {
            case .standard:    return .filled
            case .subtle:      return .subtle
            case .destructive: return .filled
            }
        }
        
        var topPadding: CGFloat {
            switch self {
            case .standard:    return 10
            case .subtle:      return 0
            case .destructive: return 10
            }
        }
        
        var bottomPadding: CGFloat {
            switch self {
            case .standard:    return 10
            case .subtle:      return 0
            case .destructive: return 10
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .standard:    return .white
            case .subtle:      return .clear
            case .destructive: return .white
            }
        }
    }
}
