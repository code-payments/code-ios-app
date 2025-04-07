//
//  PartialSheet.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct PartialSheet<T>: View where T: View {
    
    public let background: Color
    public let canDismiss: Bool
    public let content: () -> T
    
    @State private var displayHeight: CGFloat = 0
    
    public init(background: Color = .backgroundMain, canDismiss: Bool = true, @ViewBuilder content: @escaping () -> T) {
        self.background = background
        self.canDismiss = canDismiss
        self.content = content
    }
    
    public var body: some View {
        Background(color: background) {
            content()
                .overlay {
                    GeometryReader { g in
                        Color.clear
                            .preference(key: LayoutHeightPreferenceKey.self, value: g.size.height)
                    }
                }
        }
        .onPreferenceChange(LayoutHeightPreferenceKey.self) { value in
            displayHeight = value ?? 0
        }
        .presentationDetents([.height(displayHeight)])
        .interactiveDismissDisabled(!canDismiss)
    }
}

private struct LayoutHeightPreferenceKey: PreferenceKey {
    typealias Value = CGFloat?

    static let defaultValue: Value = nil

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue() ?? value
    }
}
