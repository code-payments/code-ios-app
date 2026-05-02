//
//  Background.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Background<Content>: View where Content: View {
    public var background: AnyView
    public var content: Content
    
    // MARK: - Init -
    
    public init(color: Color, @ViewBuilder content: () -> Content) {
        self.background = AnyView(color)
        self.content = content()
    }

    // MARK: - Body -

    public var body: some View {
        content
            .background {
                background
                    .ignoresSafeArea()
            }
    }
}
