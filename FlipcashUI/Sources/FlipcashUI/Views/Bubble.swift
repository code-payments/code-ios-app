//
//  Bubble.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// A count badge in a capsule; counts above 99 read "99+".
public struct Bubble: View {
    
    public let size: Size
    public let count: Int
    public let color: Color

    public init(size: Size, count: Int, color: Color = .textSuccess) {
        self.size = size
        self.count = count
        self.color = color
    }

    public var body: some View {
        Text(UnreadCountLabel.text(for: count))
            .foregroundStyle(.textMain)
            .font(size.font)
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(minWidth: size.dimension, minHeight: size.dimension)
            .background(color)
            .clipShape(.capsule)
    }
}

extension Bubble {
    public enum Size {
        
        case regular
        case large
        case extraLarge
        
        var dimension: CGFloat {
            switch self {
            case .regular:    return 16
            case .large:      return 22
            case .extraLarge: return 24
            }
        }
        
        var font: Font {
            switch self {
            case .regular:    return .appTextHeading
            case .large:      return .appTextSmall
            case .extraLarge: return .appTextMedium
            }
        }
    }
}
