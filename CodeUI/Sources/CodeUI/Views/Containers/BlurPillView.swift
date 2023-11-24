//
//  BlurPillView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct BlurredPillView<Content>: View where Content: View {
    
    public let style: UIBlurEffect.Style
    public let builder: () -> Content
    
    public init(style: UIBlurEffect.Style = .systemUltraThinMaterial, @ViewBuilder builder: @escaping () -> Content) {
        self.style = style
        self.builder = builder
    }
    
    public var body: some View {
        BlurView(style: style) {
            VStack(spacing: 0) {
                builder()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat.greatestFiniteMagnitude))
    }
}

struct BlurPillView_Previews: PreviewProvider {
    static var previews: some View {
        BlurredPillView {
            Text("Sample")
                .foregroundColor(.white)
                .padding(20.0)
        }
        .previewLayout(.fixed(width: 200.0, height: 100.0))
    }
}

#endif
