//
//  SystemCircle.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct SystemCircle<Content>: View where Content: View {
    
    private let content: Content
    private let color: Color
    
    public init(content: Content, color: Color) {
        self.content = content
        self.color = color
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.07))
                .background(
                    Circle()
                        .strokeBorder(color.opacity(0.1), lineWidth: 1)
                )
            content
                .foregroundColor(color)
        }
        .frame(width: 40, height: 40)
    }
}

extension SystemCircle where Content == Image {
    public init(system: SystemSymbol, color: Color) {
        self.init(content: Image(systemName: system.rawValue), color: color)
    }
}

extension SystemCircle where Content == Text {
    public init(text: String, color: Color) {
        self.init(content: Text(text), color: color)
    }
}

// MARK: - Previews -

struct SystemCircle_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                SystemCircle(system: .arrowUp, color: .textMain)
                SystemCircle(system: .arrowDown, color: .textMain)
                SystemCircle(text: "SD", color: .textMain)
            }
        }
        .accentColor(.textMain)
        .previewLayout(.fixed(width: 200, height: 250))
    }
}

