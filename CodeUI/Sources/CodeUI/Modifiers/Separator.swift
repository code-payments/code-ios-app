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
    public var alignment: HorizontalAlignment
    
    public init(color: Color, position: Position = .bottom, alignment: HorizontalAlignment = .leading) {
        self.color     = color
        self.position  = position
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
            .frame(height: Screen.pixelSize)
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
}

public struct HSeparator: ViewModifier {
    
    public var color: Color
    public var position: Position
    public var alignment: VerticalAlignment
    
    public init(color: Color, position: Position = .trailing, alignment: VerticalAlignment = .center) {
        self.color     = color
        self.position  = position
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
            .frame(width: Screen.pixelSize)
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
}

private enum Screen {
    #if canImport(UIKit)
    static var pixelSize: CGFloat = 1.0 / UIScreen.main.scale
    #else
    static var pixelSize: CGFloat = 1.0
    #endif
}

// MARK: - View -

extension View {
    public func vSeparator(color: Color, position: VSeparator.Position = .bottom, alignment: HorizontalAlignment = .leading) -> some View {
        modifier(
            VSeparator(
                color: color,
                position: position,
                alignment: alignment
            )
        )
    }
}
 
extension View {
    public func hSeparator(color: Color, position: HSeparator.Position = .trailing, alignment: VerticalAlignment = .center) -> some View {
        modifier(
            HSeparator(
                color: color,
                position: position,
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
                        .vSeparator(color: .white)
                }
            }
        }
    }
}
