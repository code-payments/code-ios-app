//
//  BlurView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct BlurView<Content>: View where Content: View {
    
    public let style: UIBlurEffect.Style
    public let builder: () -> Content
    
    public init(style: UIBlurEffect.Style = .systemUltraThinMaterial, @ViewBuilder builder: @escaping () -> Content) {
        self.style = style
        self.builder = builder
    }
    
    public var body: some View {
        ZStack {
            builder()
        }
        .background(
            BlurViewContainer(style: style)
        )
    }
}

// MARK: - BlueViewContainer -

struct BlurViewContainer: View, UIViewRepresentable {
    
    let style: UIBlurEffect.Style
    
    init(style: UIBlurEffect.Style) {
        self.style = style
    }
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - Previews -

struct BlurView_Previews: PreviewProvider {
    static var previews: some View {
        BlurView {
            Text("Sample")
                .foregroundColor(.white)
                .padding(20.0)
        }
        .previewLayout(.fixed(width: 200.0, height: 100.0))
    }
}

#endif
