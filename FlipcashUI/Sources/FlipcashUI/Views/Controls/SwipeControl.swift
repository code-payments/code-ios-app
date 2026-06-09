//
//  SwipeControl.swift
//  FlipcashUI
//
//  Created by Raul Riera.
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// A slide-to-confirm control. The user drags the knob along the track; once it
/// passes the commit threshold the `action` runs, showing a loading indicator
/// and then a success checkmark before the knob resets.
///
/// The knob commits when dragged past 70% of the track, or past 50% with a fast
/// release velocity.
///
/// ```swift
/// SwipeControl(text: "Swipe to Send") {
///     try await session.send(amount)
/// }
/// ```
public struct SwipeControl: View {

    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled

    @State private var knobX: CGFloat = 0
    @State private var state: KnobState = .normal

    private let text: String
    private let action: ThrowingAction
    private let completion: ThrowingAction?

    public init(text: String, action: @escaping ThrowingAction, completion: ThrowingAction? = nil) {
        self.text = text
        self.action = action
        self.completion = completion
    }

    public var body: some View {
        GeometryReader { geometry in
            let maxX = geometry.size.width - Layout.knobSize.width

            SwipingTrack(text: text, maxX: maxX, knobX: knobX, isNormal: state == .normal) {
                Task { await commit(maxX: maxX) }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Layout.height)
        .background(.action.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.buttonRadius))
        .compositingGroup()
        .clipShape(.rect(cornerRadius: Metrics.buttonRadius))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                    .stroke(Metrics.inputFieldStrokeColor(highlighted: false), lineWidth: 1 / displayScale)

                switch state {
                case .normal:
                    EmptyView()
                case .loading:
                    LoadingView(color: .gray, style: .medium)
                case .success:
                    Image.asset(.checkmark)
                        .renderingMode(.template)
                        .foregroundStyle(.textMain)
                }
            }
            .animation(nil, value: state)
        }
        .opacity(isEnabled ? 1 : Layout.disabledOpacity)
        .accessibilityRepresentation {
            Button(text) {
                Task {
                    do {
                        try await action()
                        try await completion?()
                    } catch {}
                }
            }
        }
    }

    private func commit(maxX: CGFloat) async {
        state = .loading
        knobX = maxX + Layout.knobSize.width * 2
        do {
            try await action()
            state = .success
            try await completion?()
            try await Task.delay(seconds: 2)
        } catch {}
        state = .normal
        knobX = 0
    }
}

/// Owns the high-frequency drag and idle-nudge state, and renders the label and
/// knob together so a drag (or nudge) re-renders only the track, not the
/// control's background, border, or status overlay. As the knob advances it
/// masks the label away from the left and fades the still-visible remainder
/// toward transparent.
private struct SwipingTrack: View {

    let text: String
    let maxX: CGFloat
    let knobX: CGFloat
    let isNormal: Bool
    let onCommit: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    @GestureState private var dragOffset: CGFloat? = nil
    @State private var isNudging = false

    var body: some View {
        let position = knobX + (dragOffset ?? 0)
        let leadingX = position + Layout.knobSize.width
        let labelOpacity = maxX > 0 ? 1 - min(max(position / maxX, 0), 1) : 1
        let nudgeX: CGFloat = (isNormal && isEnabled && dragOffset == nil && isNudging) ? Layout.nudgeOffset : 0

        ZStack(alignment: .leading) {
            Text(text)
                .lineLimit(1)
                .font(.appTextMedium)
                .foregroundStyle(.textMain)
                .padding(.horizontal, Layout.knobSize.width)
                .frame(maxWidth: .infinity) // span the track so the mask offset below is in track coordinates
                .mask(alignment: .leading) {
                    Color.black
                        .opacity(labelOpacity)
                        .offset(x: leadingX)
                        .animation(.springFastestDamped, value: leadingX)
                }
                .opacity(isNormal ? 1 : 0)

            RoundedRectangle(cornerRadius: Layout.knobCornerRadius)
                .fill(.action)
                .frame(width: Layout.knobSize.width, height: Layout.knobSize.height)
                .overlay {
                    Image.system(.arrowRight)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Layout.arrowSize, height: Layout.arrowSize)
                        .foregroundStyle(.textAction)
                }
                .offset(x: position + nudgeX)
                .animation(.springFastestDamped, value: position + nudgeX)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragOffset) { value, dragState, transaction in
                            transaction.disablesAnimations = true
                            dragState = min(max(value.translation.width, 0), maxX)
                        }
                        .onEnded { value in
                            let offset = min(max(value.translation.width, 0), maxX)
                            let velocity = value.predictedEndLocation.x - value.location.x
                            let percent = maxX > 0 ? offset / maxX : 0
                            guard percent > Layout.commitFraction
                                || (percent > Layout.velocityAssistFraction && velocity > Layout.velocityAssistMinimum)
                            else { return }
                            onCommit()
                        }
                )
                .disabled(!isNormal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            do {
                try await Task.delay(seconds: 3)
                while true {
                    isNudging = true
                    try await Task.delay(milliseconds: 150)
                    isNudging = false
                    try await Task.delay(seconds: 4)
                }
            } catch {
                isNudging = false
            }
        }
    }
}

private enum Layout {
    static let height: CGFloat = Metrics.buttonHeight
    static let knobSize = CGSize(width: 60, height: 52)
    static let knobCornerRadius: CGFloat = 4
    static let arrowSize: CGFloat = 18
    static let nudgeOffset: CGFloat = 20
    static let disabledOpacity: CGFloat = 0.4

    static let commitFraction: CGFloat = 0.7
    static let velocityAssistFraction: CGFloat = 0.5
    static let velocityAssistMinimum: CGFloat = 200
}

private enum KnobState {
    case normal
    case loading
    case success
}

#Preview {
    Background(color: .backgroundMain) {
        VStack(spacing: 40) {
            SwipeControl(text: "Swipe to Send") {
                try await Task.delay(seconds: 2)
            }

            SwipeControl(text: "Swipe to Pay") {
                try await Task.delay(seconds: 1)
            }

            SwipeControl(text: "Swipe to Send") {
                try await Task.delay(seconds: 1)
            }
            .disabled(true)
        }
        .padding(20)
    }
}
