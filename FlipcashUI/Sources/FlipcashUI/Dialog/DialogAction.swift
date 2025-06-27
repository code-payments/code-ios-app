//
//  DialogAction.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

public struct DialogAction {
    
    public typealias DialogActionHandler = () -> Void
    
    public let kind: Kind
    public let title: String
    public let action: DialogActionHandler
    
    init(kind: Kind, title: String, action: @escaping DialogActionHandler) {
        self.kind   = kind
        self.title  = title
        self.action = action
    }
    
    public static func standard(_ title: String, action: @escaping DialogActionHandler) -> Self {
        self.init(
            kind: .standard,
            title: title,
            action: action
        )
    }
    
    public static func outline(_ title: String, action: @escaping DialogActionHandler) -> Self {
        self.init(
            kind: .outline,
            title: title,
            action: action
        )
    }
    
    public static func subtle(_ title: String, action: @escaping DialogActionHandler) -> Self {
        self.init(
            kind: .subtle,
            title: title,
            action: action
        )
    }
    
    public static func destructive(_ title: String, action: @escaping DialogActionHandler) -> Self {
        self.init(
            kind: .destructive,
            title: title,
            action: action
        )
    }
    
    // MARK: - Pre-baked -
    
    public static func okay(kind: Kind, action: @escaping DialogActionHandler = {}) -> Self {
        self.init(
            kind: kind,
            title: "OK",
            action: action
        )
    }
    
    public static func cancel(action: @escaping DialogActionHandler = {}) -> Self {
        self.init(
            kind: .subtle,
            title: "Cancel",
            action: action
        )
    }
    
    public static func notNow(action: @escaping DialogActionHandler = {}) -> Self {
        self.init(
            kind: .subtle,
            title: "Not Now",
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
        case outline
        
        var buttonStyle: DialogButton.Style {
            switch self {
            case .standard:    return .primary
            case .subtle:      return .subtle
            case .destructive: return .destructive
            case .outline:     return .outline
            }
        }
        
        var topPadding: CGFloat {
            switch self {
            case .standard:    return 10
            case .subtle:      return 0
            case .destructive: return 10
            case .outline:     return 10
            }
        }
        
        var bottomPadding: CGFloat {
            switch self {
            case .standard:    return 10
            case .subtle:      return 0
            case .destructive: return 10
            case .outline:     return 10
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .standard:    return .white
            case .subtle:      return .clear
            case .destructive: return .white
            case .outline:     return .clear
            }
        }
    }
}
