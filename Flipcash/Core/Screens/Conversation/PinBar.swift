//
//  PinBar.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// The pinned message under the navigation bar: a title and one line of the pin it shows. Tapping
/// the bar jumps to that message; the list button opens every pin.
struct PinBar: View {

    /// The line the bar shows for the pin it's on.
    let snippet: String
    /// How many pins the viewer can see, which the segments count.
    let count: Int
    /// Where the shown pin sits among them, newest first.
    let index: Int
    let onTap: () -> Void
    let onList: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    if count > 1 {
                        PinBarSegments(count: count, index: index)
                    }
                    Image.system(.pinFill)
                        .foregroundStyle(Color.textMain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pinned message")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                        Text(snippet)
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows the message in the chat")
            .accessibilityIdentifier("pin-bar")

            Button(action: onList) {
                Image.system(.listBullet)
                    .foregroundStyle(Color.textMain)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pinned Messages")
            .accessibilityIdentifier("pin-bar-list")
        }
        // The list button fills the bar's height, not the overlay's.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: BarMetrics.contentHeight)
        .contentShape(.rect(cornerRadius: BarMetrics.cornerRadius))
        .anchorGlass()
    }
}

/// The bar's leading segments, one per pin, with the shown one lit, as Telegram marks which pin
/// a cycling bar is on. Past three pins it shows a window of three that follows the lit one.
private struct PinBarSegments: View {

    let count: Int
    let index: Int

    private static let width: CGFloat = 3
    private static let length: CGFloat = 10
    private static let gap: CGFloat = 2
    private static let window = 3

    var body: some View {
        let shown = min(count, Self.window)
        let start = max(0, min(index - 1, count - shown))
        VStack(spacing: Self.gap) {
            ForEach(start..<(start + shown), id: \.self) { segment in
                Capsule()
                    .fill(segment == index ? Color.textMain : Color.textSecondary.opacity(0.4))
                    .frame(width: Self.width, height: Self.length)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The pin button in the navigation bar's trailing slot while the request strip holds the slot
/// under the bar. Opens every pin.
struct PinToolbarButton: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image.system(.pinFill)
                .foregroundStyle(Color.textMain)
                .frame(width: Metrics.buttonHeightThin, height: Metrics.buttonHeightThin)
                .overlayGlassBackground(in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("Pinned Messages")
        .accessibilityIdentifier("pin-toolbar-button")
    }
}
