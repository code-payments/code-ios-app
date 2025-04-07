//
//  InputContainer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct InputContainer<T>: View where T: View {
    
    public let size: Size
    public let highlighted: Bool
    public let content: () -> T
    
    // MARK: - Init -
    
    public init(size: Size = .regular, highlighted: Bool = false, @ViewBuilder content: @escaping () -> T) {
        self.size = size
        self.highlighted = highlighted
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        VStack {
            content()
        }
        .frame(height: size.height)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                .strokeBorder(Metrics.inputFieldStrokeColor(highlighted: highlighted), lineWidth: Metrics.inputFieldBorderWidth(highlighted: highlighted))
                .background(background())
        )
    }
    
    @ViewBuilder private func background() -> some View {
        if highlighted {
            Color.backgroundRow
                .overlay(
                    Color.white.opacity(0.05)
                )
                .cornerRadius(Metrics.buttonRadius)
        } else {
            Color.backgroundRow
                .cornerRadius(Metrics.buttonRadius)
        }
    }
}

extension InputContainer {
    public enum Size {
        case small
        case regular
        case custom(CGFloat)
        
        var height: CGFloat {
            switch self {
            case .regular: return 56
            case .small:   return 45
            case .custom(let height):
                return height
            }
        }
    }
}
