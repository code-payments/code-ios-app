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
    public var insets: EdgeInsets

    @Environment(\.displayScale) private var displayScale
    
    public init(color: Color, position: Position, weight: Weight, alignment: HorizontalAlignment, insets: EdgeInsets) {
        self.color     = color
        self.position  = position
        self.weight    = weight
        self.alignment = alignment
        self.insets    = insets
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
            .frame(height: weight.pixelSize(for: displayScale))
            .frame(maxWidth: .infinity)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }
}

extension VSeparator {
    public struct Position: OptionSet, Sendable {

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

        func pixelSize(for displayScale: CGFloat) -> CGFloat {
            switch self {
            case .regular: 1.0 / displayScale
            case .medium:  1.0
            }
        }
    }
}

// MARK: - View -

extension View {
    public func vSeparator(color: Color, position: VSeparator.Position = .bottom, weight: VSeparator.Weight = .regular, alignment: HorizontalAlignment = .leading, insets: EdgeInsets = .zero) -> some View {
        modifier(
            VSeparator(
                color: color,
                position: position,
                weight: weight,
                alignment: alignment,
                insets: insets
            )
        )
    }
}

extension EdgeInsets {
    public static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

// MARK: - Previews -

struct Separator_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            LazyTable {
                ForEach(0..<100, id: \.self) { index in
                    Text("Hello")
                        .foregroundStyle(.white)
                        .padding([.top, .bottom], 20)
                        .vSeparator(color: .white, weight: .medium)
                }
            }
        }
    }
}
