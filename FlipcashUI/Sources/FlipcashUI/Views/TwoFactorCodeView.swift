//
//  TwoFactorCodeView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct TwoFactorCodeView: View {
    
    @Binding public var content: String
    
    private let digitCount: Int

    private let fillsWidth: Bool

    private var activeIndex: Int {
        content.count
    }

    // MARK: - Init -

    /// - Parameter fillsWidth: stretches the boxes across the offered width, so the row starts
    ///   and ends at the edges of the text above and below it. Off, the boxes keep a fixed width.
    public init(digitCount: Int = 6, fillsWidth: Bool = false, content: Binding<String>) {
        self.digitCount = digitCount
        self.fillsWidth = fillsWidth
        self._content = content
    }
    
    public var body: some View {
        HStack {
            ForEach(Array(characters(content).enumerated()), id: \.0) { index, character in
                InputContainer(size: .small, highlighted: index == activeIndex) {
                    if character.count > 0 {
                        Text(character)
                            .font(.appTextLarge)
                            .foregroundStyle(.textMain)
                            .transition(
                                AnyTransition
                                    .opacity
                                    .combined(with: .scale)
                            )
                    }
                }
                .frame(width: fillsWidth ? nil : 35)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
        }
    }
    
    private func characters(_ string: String) -> [String] {
        var characters = Array(repeating: "", count: digitCount)
        string.enumerated().forEach { index, character in
            if index < digitCount {
                characters[index] = String(character)
            }
        }
        return characters
    }
}

// MARK: - Previews -

struct TwoFactorCodeView_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                TwoFactorCodeView(content: .constant("123456"))
                TwoFactorCodeView(content: .constant(""))
                TwoFactorCodeView(content: .constant("987"))
            }
        }
        .previewLayout(.fixed(width: 320, height: 200))

    }
}
