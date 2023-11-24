//
//  TextBubble.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct TextBubble: View {
    
    public let style: Style
    public let text: String
    public let paddingVertical: CGFloat?
    public let paddingHorizontal: CGFloat?
    
    // MARK: - Init -
    
    public init(style: Style, text: String, paddingVertical: CGFloat? = nil, paddingHorizontal: CGFloat? = nil) {
        self.style = style
        self.text = text
        self.paddingVertical = paddingVertical
        self.paddingHorizontal = paddingHorizontal
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack {
            Text(text)
                .font(.appTextSmall)
                .foregroundColor(style.textColor)
        }
        .padding([.top, .bottom], 5 + (paddingVertical ?? 0))
        .padding([.leading, .trailing], 10 + (paddingHorizontal ?? 0))
        .background(style.background())
    }
}

// MARK: - Style -

extension TextBubble {
    public enum Style {
        
        case filled
        case outline
        
        var textColor: Color {
            switch self {
            case .filled:  return .backgroundMain
            case .outline: return .textMain
            }
        }
        
        @ViewBuilder func background() -> some View {
            switch self {
            case .filled:
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.textMain)
                
            case .outline:
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Color.textMain, lineWidth: Metrics.buttonLineWidth)
            }
        }
    }
}

// MARK: - Previews -

struct TextBubble_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                TextBubble(style: .filled, text: "OK")
                TextBubble(style: .filled, text: "Close")
                TextBubble(style: .filled, text: "Error")
                TextBubble(style: .filled, text: "Warning")
            }
        }
    }
}
