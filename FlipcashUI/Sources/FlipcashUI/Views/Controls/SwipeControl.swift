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
        ZStack {
            Text(text)
                .lineLimit(1)
                .font(.appTextMedium)
                .foregroundStyle(.textMain)
                .padding(.horizontal, Layout.knobSize.width)
                .opacity(state == .normal ? 1 : 0)

            GeometryReader { geometry in
                let maxX = geometry.size.width - Layout.knobSize.width

                Knob(maxX: maxX, knobX: knobX, isIdle: state == .normal) {
                    Task {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
                    .stroke(.textSecondary.opacity(0.3), lineWidth: 1 / displayScale)

                switch state {
                case .normal:
                    EmptyView()
                case .loading:
                    LoadingView(color: .gray, style: .medium)
                case .success:
                    Image.asset(.checkmarkLarge)
                        .renderingMode(.template)
                        .foregroundStyle(.textSuccess)
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
}

/// The draggable knob. Owns the high-frequency drag and idle-nudge state so a
/// drag or nudge re-renders only the knob, not the whole control.
private struct Knob: View {

    let maxX: CGFloat
    let knobX: CGFloat
    let isIdle: Bool
    let onCommit: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    @GestureState private var dragOffset: CGFloat? = nil
    @State private var isNudging = false

    var body: some View {
        let nudgeX: CGFloat = (isIdle && isEnabled && dragOffset == nil && isNudging) ? Layout.nudgeOffset : 0

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
            .offset(x: knobX + (dragOffset ?? 0) + nudgeX)
            .animation(.springFastestDamped, value: dragOffset)
            .animation(.springFastestDamped, value: knobX)
            .animation(.springFastestDamped, value: isNudging)
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
            .disabled(!isIdle)
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
