//
//  Separator.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct VSeparator: ViewModifier {
    
    public var color: Color
    public var position: Position
    public var weight: Weight
    public var alignment: HorizontalAlignment
    
    public init(color: Color, position: Position, weight: Weight, alignment: HorizontalAlignment) {
        self.color     = color
        self.position  = position
        self.weight    = weight
        self.alignment = alignment
    }
    
    public func body(content: Content) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            if position.contains(.top) {
                separator()
            }
            content
            if position.contains(.bottom) {
                separator()
            }
        }
    }
    
    @ViewBuilder private func separator() -> some View {
        Rectangle()
            .fill(color)
            .frame(height: weight.pixelSize)
            .frame(maxWidth: .infinity)
    }
}

extension VSeparator {
    public struct Position: OptionSet {
        
        public let rawValue: UInt8
        
        public static let top    = Position(rawValue: 1 << 0)
        public static let bottom = Position(rawValue: 1 << 1)
        
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
    
    public enum Weight {
        case regular
        case medium
        
        var pixelSize: CGFloat {
            switch self {
            case .regular: Screen.pixelSize
            case .medium:  Screen.pointSize
            }
        }
    }
}

public struct HSeparator: ViewModifier {
    
    public var color: Color
    public var position: Position
    public var weight: Weight
    public var alignment: VerticalAlignment
    
    public init(color: Color, position: Position, weight: Weight, alignment: VerticalAlignment) {
        self.color     = color
        self.position  = position
        self.weight    = weight
        self.alignment = alignment
    }
    
    public func body(content: Content) -> some View {
        HStack(alignment: alignment, spacing: 0) {
            if position.contains(.leading) {
                separator()
            }
            content
            if position.contains(.trailing) {
                separator()
            }
        }
    }
    
    @ViewBuilder private func separator() -> some View {
        Rectangle()
            .fill(color)
            .frame(width: weight.pixelSize)
            .frame(maxHeight: .infinity)
    }
}

extension HSeparator {
    public struct Position: OptionSet {
        
        public let rawValue: UInt8
        
        public static let leading  = Position(rawValue: 1 << 0)
        public static let trailing = Position(rawValue: 1 << 1)
        
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
    
    public enum Weight {
        case regular
        case medium
        
        var pixelSize: CGFloat {
            switch self {
            case .regular: Screen.pixelSize
            case .medium:  Screen.pointSize
            }
        }
    }
}

private enum Screen {
    static var pointSize: CGFloat = 1.0
    #if canImport(UIKit)
    static var pixelSize: CGFloat = 1.0 / UIScreen.main.scale
    #else
    static var pixelSize: CGFloat = 1.0
    #endif
}

// MARK: - View -

extension View {
    public func vSeparator(color: Color, position: VSeparator.Position = .bottom, weight: VSeparator.Weight = .regular, alignment: HorizontalAlignment = .leading) -> some View {
        modifier(
            VSeparator(
                color: color,
                position: position,
                weight: weight,
                alignment: alignment
            )
        )
    }
}
 
extension View {
    public func hSeparator(color: Color, position: HSeparator.Position = .trailing, weight: HSeparator.Weight = .regular, alignment: VerticalAlignment = .center) -> some View {
        modifier(
            HSeparator(
                color: color,
                position: position,
                weight: weight,
                alignment: alignment
            )
        )
    }
}

// MARK: - Previews -

struct Separator_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            LazyTable {
                ForEach(0..<100, id: \.self) { index in
                    Text("Hello")
                        .foregroundColor(.white)
                        .padding([.top, .bottom], 20)
                        .vSeparator(color: .white, weight: .medium)
                }
            }
        }
    }
}
