//
//  Loading.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Loading: ViewModifier {
    
    public var active: Bool
    public var text: String?
    public var color: Color
    public var padding: CGFloat
    public var showOverlay: Bool
    
    public init(active: Bool, text: String?, color: Color, padding: CGFloat, showOverlay: Bool) {
        self.active = active
        self.text  = text
        self.color = color
        self.padding = padding
        self.showOverlay = showOverlay
    }
    
    public func body(content: Content) -> some View {
        ZStack {
            content
            if active {
                VStack(spacing: 20) {
                    LoadingView(color: color, style: .large)
                    if let text {
                        Text(text)
                            .font(.appTextMedium)
                            .foregroundColor(color)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, padding)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(showOverlay ? 0.8 : 0.0))
                .animation(.linear(duration: 0.1), value: active)
            }
        }
    }
}

// MARK: - View -

extension View {
    public func loading(active: Bool, text: String? = nil, color: Color, padding: CGFloat = 20, showOverlay: Bool = true) -> some View {
        modifier(
            Loading(
                active: active,
                text: text,
                color: color,
                padding: padding,
                showOverlay: showOverlay
            )
        )
    }
}

// MARK: - Previews -

struct Loading_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .green) {
            Button {
                // Do nothing
            } label: {
                Circle()
                    .fill(.red)
                    .frame(width: 250, height: 250)
            }
                
        }
        .loading(
            active: true,
            text: "Grabbing cash",
            color: .white
//            showOverlay: false
        )
    }
}
