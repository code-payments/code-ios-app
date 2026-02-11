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
    private let duration: TimeInterval

    @State private var progress: CGFloat = 0

    public init(
        lineWidth: CGFloat = 5,
        ringColor: Color = .white.opacity(0.3),
        highlightColor: Color = .white,
        duration: TimeInterval
    ) {
        self.lineWidth = lineWidth
        self.ringColor = ringColor
        self.highlightColor = highlightColor
        self.duration = duration
    }

    public var body: some View {
        // GeometryReader with explicit frame/position is required to prevent the rotating
        // segment from drifting away from the background ring. Using overlay or ZStack alone
        // causes coordinate space misalignment during animation in certain layout contexts.
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Background ring
                Circle()
                    .stroke(ringColor, lineWidth: lineWidth)
                    .frame(width: size, height: size)
                    .position(center)

                // Progress fill
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(highlightColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .position(center)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        CircularLoadingView(duration: 5)
            .frame(width: 64, height: 64)
    }
}
