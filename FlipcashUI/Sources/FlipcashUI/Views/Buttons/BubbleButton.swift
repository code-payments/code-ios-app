//
//  BubbleButton.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

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
    }
}
