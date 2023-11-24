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
    
    public init(size: Size, count: Int) {
        self.size = size
        self.count = count
    }
    
    public var body: some View {
        Text("\(count)")
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
        
        var dimension: CGFloat {
            switch self {
            case .regular: return 16
            case .large:   return 22
            }
        }
        
        var font: Font {
            switch self {
            case .regular: return .appTextHeading
            case .large:   return .appTextSmall
            }
        }
    }
}
