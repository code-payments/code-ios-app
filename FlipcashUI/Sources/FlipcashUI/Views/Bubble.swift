//
//  Bubble.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Bubble: View {
    
    public let size: Size
    public let count: Int
    public let hasMore: Bool
    
    private var decoration: String {
        if hasMore {
            return "+"
        } else {
            return ""
        }
    }
    
    public init(size: Size, count: Int, hasMore: Bool = false) {
        self.size = size
        self.count = count
        self.hasMore = hasMore
    }
    
    public var body: some View {
        Text("\(count)\(decoration)")
            .foregroundColor(.textMain)
            .font(size.font)
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(minWidth: size.dimension, minHeight: size.dimension)
            .background(Color.textSuccess)
            .cornerRadius(999)
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
