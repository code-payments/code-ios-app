//
//  PartialSheet.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct PartialSheet<T>: View where T: View {
    
    public let content: () -> T
    
    @State private var displayHeight: CGFloat = 0
    
    public init(@ViewBuilder content: @escaping () -> T) {
        self.content = content
    }
    
    public var body: some View {
        Background(color: .black) {
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
    }
}

private struct LayoutHeightPreferenceKey: PreferenceKey {
    typealias Value = CGFloat?

    static var defaultValue: Value = nil

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = nextValue() ?? value
    }
}
