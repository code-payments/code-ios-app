//
//  Background.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Background<Content>: View where Content: View {
    private let color: Color
    private let content: Content

    // MARK: - Init -

    public init(color: Color, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    // MARK: - Body -

    // ZStack (not `.background`) — on iOS 26 the modifier form exposes
    // content's TupleView at the top of the wrapper, causing parent
    // `.toolbar { ToolbarItem }` items to duplicate per top-level sibling.
    public var body: some View {
        ZStack {
            color
                .ignoresSafeArea()
                .allowsHitTesting(false)
            content
        }
    }
}
