//
//  CircularLoadingView.swift
//  FlipcashUI
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import SwiftUI

public struct CircularLoadingView: View {
    private let lineWidth: CGFloat
    private let ringColor: Color
    private let highlightColor: Color

    @State private var isAnimating = false

    public init(
        lineWidth: CGFloat = 3,
        ringColor: Color = .white.opacity(0.3),
        highlightColor: Color = .white
    ) {
        self.lineWidth = lineWidth
        self.ringColor = ringColor
        self.highlightColor = highlightColor
    }

    public var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(ringColor, lineWidth: lineWidth)

            // Animated highlight segment
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(highlightColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 1.0)
                    .repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    ZStack {
        Color.black
        CircularLoadingView()
            .frame(width: 64, height: 64)
    }
}
