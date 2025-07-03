//
//  StrokedRectangle.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-07-03.
//

import SwiftUI

public struct StrokedRectangle: View {

    public let style: Style
    public let cornerRadius: CGFloat
    public let lineWidth: CGFloat
    
    public init(style: Style, cornerRadius: CGFloat = Metrics.boxRadius, lineWidth: CGFloat = 1) {
        self.style        = style
        self.cornerRadius = cornerRadius
        self.lineWidth    = lineWidth
    }
    
    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(style.fillColor)
            .strokeBorder(style.strokeColor, lineWidth: lineWidth)
    }
}

extension StrokedRectangle {
    public enum Style {
        
        case brightGreen
        case darkGreen
        case white
        
        var strokeColor: Color {
            switch self {
            case .brightGreen:
                Color(r: 77, g: 153, b: 97)
            case .darkGreen:
                Color(r: 48, g: 64, b: 55)
            case .white:
                Color.clear
            }
        }
        
        var fillColor: Color {
            switch self {
            case .brightGreen:
                Color(r: 67, g: 144, b: 84)
            case .darkGreen:
                Color(r: 12, g: 37, b: 24)
            case .white:
                Color.white
            }
        }
    }
}
