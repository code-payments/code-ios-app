//
//  TrayOptionRow.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// One choice in a tray's list: an optional icon, a title, and a check while it is selected. A tap
/// plays a selection haptic on touch down.
///
/// Stack several at ``TrayOptionRow/gap`` as a tray's content. A row either applies its choice
/// on tap or selects it for the tray's CTA to confirm; `isSelected` draws the latter.
public struct TrayOptionRow: View {

    private let title: String
    private let icon: Icon?
    private let isSelected: Bool
    private let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a row; `isSelected` shows the check and the raised fill.
    public init(_ title: String, icon: Icon? = nil, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image.icon(icon)
                        .iconSize(TrayMetrics.rowIconSize)
                }
                Text(title)
                    // SF Pro until type tokens are decided (Phase 2).
                    .font(.system(size: TrayMetrics.scaled(TrayMetrics.rowTextSize, .body, dynamicTypeSize), weight: TrayMetrics.rowTextWeight))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image.icon(.checkmark1)
                    .iconSize(20)
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(Color.textMain)
            .padding(.horizontal, 16)
            .frame(minHeight: TrayMetrics.rowHeight)
            // Selection snaps, fill and check alike; only the press moves.
            .background {
                RoundedRectangle(cornerRadius: TrayMetrics.rowRadius, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? TrayMetrics.rowSelectedFillOpacity : TrayMetrics.rowFillOpacity))
            }
            .contentShape(.rect(cornerRadius: TrayMetrics.rowRadius, style: .continuous))
            // The release's transaction reaches the label as the selection lands; without this the
            // tapped row fades its check and fill in.
            .animation(nil, value: isSelected)
        }
        .buttonStyle(TrayRowPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A tray row or tile's press: a slight scale, or a dim under Reduce Motion, with the haptic on touch down.
struct TrayRowPressStyle: ButtonStyle {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        return configuration.label
            .modifier(Press(isPressed: isPressed, reduceMotion: reduceMotion))
            // On touch down, as a physical control answers, not on release.
            .onChange(of: isPressed) { _, isPressed in
                if isPressed { TrayMetrics.rowHaptic.play() }
            }
    }
}

/// The press's scale or dim, animated on its own.
private struct Press: ViewModifier {

    let isPressed: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        // Scoped to the press itself: a selection that lands as the finger lifts must not ride the
        // release's spring.
        content
            .animation(.spring(duration: 0.2, bounce: 0)) { content in
                content
                    .scaleEffect(!reduceMotion && isPressed ? TrayMetrics.rowPressScale : 1)
                    .opacity(reduceMotion && isPressed ? 0.7 : 1)
            }
    }
}

extension TrayOptionRow {
    /// The space between stacked rows. // LOCAL-TUNER
    @MainActor public static var gap: CGFloat { TrayMetrics.rowGap } // LOCAL-TUNER
}
