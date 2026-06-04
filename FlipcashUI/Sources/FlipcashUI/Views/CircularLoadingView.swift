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
        ProgressView(value: progress)
            .progressViewStyle(
                RingProgressViewStyle(
                    lineWidth: lineWidth,
                    ringColor: ringColor,
                    highlightColor: highlightColor
                )
            )
            .onAppear {
                withAnimation(.linear(duration: duration)) {
                    progress = 1.0
                }
            }
    }
}

// MARK: - Style -

/// Draws the determinate ring from the progress fraction. `GeometryReader` +
/// explicit `.position` keep the rotating segment aligned to the background
/// ring; a bare `ZStack`/overlay drifts off-axis during the animation in some
/// layout contexts.
private struct RingProgressViewStyle: ProgressViewStyle {

    let lineWidth: CGFloat
    let ringColor: Color
    let highlightColor: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: lineWidth)
                    .frame(width: size, height: size)
                    .position(center)

                Circle()
                    .trim(from: 0, to: CGFloat(configuration.fractionCompleted ?? 0))
                    .stroke(highlightColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .position(center)
            }
        }
    }
}

// MARK: - Previews -

#Preview("Animated") {
    ZStack {
        Color.black
        CircularLoadingView(duration: 5)
            .frame(width: 64, height: 64)
    }
}

#Preview("Static fractions") {
    ZStack {
        Color.black
        HStack(spacing: 24) {
            ForEach([0.0, 0.35, 0.75, 1.0], id: \.self) { value in
                ProgressView(value: value)
                    .progressViewStyle(
                        RingProgressViewStyle(
                            lineWidth: 5,
                            ringColor: .white.opacity(0.3),
                            highlightColor: .white
                        )
                    )
                    .frame(width: 48, height: 48)
            }
        }
    }
}
