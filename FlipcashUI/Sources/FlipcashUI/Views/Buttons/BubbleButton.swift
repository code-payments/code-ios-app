//
//  BubbleButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

/// A small white capsule holding one short label, with the house press.
public struct BubbleButton: View {
    
    public let font: Font
    public let text: String
    public let action: VoidAction
    
    public init(font: Font = .appTextMedium, text: String, action: @escaping VoidAction) {
        self.font = font
        self.text = text
        self.action = action
    }
    
    public var body: some View {
        Button {
            action()
        } label: {
            TextBubble(
                style: .filled,
                font: font,
                text: text,
                paddingVertical: 5,
                paddingHorizontal: 15
            )
        }
        .buttonStyle(BubblePressStyle())
    }
}

// MARK: - Style -

private struct BubblePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .buttonPress(isPressed: configuration.isPressed)
    }
}
