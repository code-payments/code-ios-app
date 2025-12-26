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
    
    public init(gradient: LinearGradient, @ViewBuilder content: () -> Content) {
        self.background = AnyView(gradient)
        self.content = content()
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ZStack {
            background
                .edgesIgnoringSafeArea(.all)
            content
        }
    }
}

// MARK: - Previews -

struct Background_Previews: PreviewProvider {
    static var previews: some View {
        Background(gradient: .background) {
            Text("")
        }
    }
}
