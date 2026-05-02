//
//  ExpandableText.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-05-02.
//

import SwiftUI

/// Multi-line text that collapses past a line limit with a gradient fade
/// and a Show More / Show Less toggle. The toggle hides automatically when
/// the text fits within `collapsedLineLimit`.
///
/// Font and foreground style are inherited from the environment — apply
/// `.font(...)` and `.foregroundStyle(...)` from the call site like a
/// normal `Text`.
public struct ExpandableText: View {
    private let text: String
    private let collapsedLineLimit: Int

    @State private var isExpanded: Bool = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    public init(_ text: String, collapsedLineLimit: Int = 5) {
        self.text = text
        self.collapsedLineLimit = collapsedLineLimit
    }

    // 0.5pt buffer guards against subpixel rendering noise between the
    // unclamped probe and the lineLimit-clamped probe at the same width.
    private var isTruncatable: Bool {
        fullHeight > collapsedHeight + 0.5
    }

    // Visible-frame height: nil until both probes have reported, then either
    // full or collapsed. Animating this (instead of toggling `lineLimit`)
    // keeps the rendered text content constant — only the clip window moves.
    private var visibleHeight: CGFloat? {
        guard fullHeight > 0, collapsedHeight > 0 else { return nil }
        return isExpanded || !isTruncatable ? fullHeight : collapsedHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: visibleHeight, alignment: .top)
                .background(alignment: .topLeading) {
                    HeightProbe<FullHeightKey>(text: text, lineLimit: nil)
                }
                .background(alignment: .topLeading) {
                    HeightProbe<CollapsedHeightKey>(text: text, lineLimit: collapsedLineLimit)
                }
                .clipped()
                .mask(FadeMask(isFaded: isTruncatable && !isExpanded))

            if isTruncatable {
                Button {
                    withAnimation(.smooth) {
                        isExpanded.toggle()
                    }
                } label: {
                    ExpandableTextToggleLabel(isExpanded: isExpanded)
                }
            }
        }
        .onPreferenceChange(FullHeightKey.self) { newValue in
            if newValue != fullHeight {
                fullHeight = newValue
            }
        }
        .onPreferenceChange(CollapsedHeightKey.self) { newValue in
            if newValue != collapsedHeight {
                collapsedHeight = newValue
            }
        }
    }
}

private struct HeightProbe<Key: PreferenceKey>: View where Key.Value == CGFloat {
    let text: String
    let lineLimit: Int?

    var body: some View {
        Text(text)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: Key.self, value: proxy.size.height)
                }
            }
    }
}

private struct FadeMask: View {
    let isFaded: Bool

    // The mask must switch instantly between gradient and solid when
    // `isFaded` flips. Without this, the outer expand/collapse animation
    // crossfades between the two mask views, dimming the visible text
    // mid-transition (the "blink").
    var body: some View {
        Group {
            if isFaded {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.65),
                        .init(color: .black.opacity(0.05), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color.black
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct ExpandableTextToggleLabel: View {
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(isExpanded ? "Show Less" : "Show More")
                .contentTransition(.identity)
            Image(systemName: "chevron.down")
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .font(.appBarButton)
        .foregroundStyle(Color.textMain)
    }
}

private struct FullHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CollapsedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews -

#Preview("Long text — collapses with toggle") {
    Background(color: .backgroundMain) {
        ScrollView {
            ExpandableText(
                "Dolore mollit et incididunt labore aliqua tempor non Lorem sit duis aute do adipisicing. Duis cillum velit ipsum nostrud aliquip magna quis. Sunt velit labore sunt sit aliqua laborum deserunt pariatur proident do elit amet officia ipsum cillum non nisi. Aliqua incididunt voluptate culpa irure occaecat aliquip eiusmod ex ipsum esse.\n Dolore mollit et incididunt labore aliqua tempor non Lorem sit duis aute do adipisicing. Duis cillum velit ipsum nostrud aliquip magna quis. Sunt velit labore sunt sit aliqua laborum deserunt pariatur proident do elit amet officia ipsum cillum non nisi. Aliqua incididunt voluptate culpa irure occaecat aliquip eiusmod ex ipsum esse."
            )
            .foregroundStyle(Color.textSecondary)
            .font(.appTextSmall)
            .padding()
        }
    }
}

#Preview("Short text — no toggle") {
    Background(color: .backgroundMain) {
        ScrollView {
            ExpandableText("Launch It V3 — a small currency for testing.")
                .foregroundStyle(Color.textSecondary)
                .font(.appTextSmall)
                .padding()
        }
    }
}

#Preview("Exactly at limit — no toggle") {
    Background(color: .backgroundMain) {
        ScrollView {
            ExpandableText("Line one\nLine two\nLine three\nLine four\nLine five")
                .foregroundStyle(Color.textSecondary)
                .font(.appTextSmall)
                .padding()
        }
    }
}
