//
//  SlidingChipPicker.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// A row of equal-width chips on grey capsules, with one white capsule that slides to the selected
/// chip instead of fading between them. A nil selection leaves every chip grey. A label that
/// doesn't fit wraps to a second line.
public struct SlidingChipPicker<Option: Hashable>: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options: [Option]
    @Binding private var selection: Option?
    private let label: (Option) -> String

    public init(_ options: [Option], selection: Binding<Option?>, label: @escaping (Option) -> String) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    /// For a picker that always has a selection.
    public init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.init(
            options,
            selection: Binding<Option?>(get: { selection.wrappedValue }, set: { if let value = $0 { selection.wrappedValue = value } }),
            label: label
        )
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.appTextSmall)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? Color.black : Color.textMain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .anchorPreference(key: ChipAnchors<Option>.self, value: .bounds) { [option: $0] }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        // Every chip takes the tallest label's height, so a wrapped label keeps the capsules uniform.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .backgroundPreferenceValue(ChipAnchors<Option>.self) { anchors in
            GeometryReader { proxy in
                ForEach(Array(anchors.keys), id: \.self) { option in
                    if let anchor = anchors[option] {
                        let rect = proxy[anchor]
                        Capsule().fill(Color.backgroundSecondary)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                // One capsule for the selection, so it slides between chips instead of fading.
                if let selection, let anchor = anchors[selection] {
                    let rect = proxy[anchor]
                    Capsule().fill(Color.white)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: selection)
    }
}

/// Each chip's bounds, so the selection capsule can be drawn once and slide between chips.
private struct ChipAnchors<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [ID: Anchor<CGRect>], nextValue: () -> [ID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var days: Int = 7
        @State private var custom: Int? = nil

        var body: some View {
            VStack(spacing: 24) {
                SlidingChipPicker([1, 3, 7, 14, 28], selection: $days) { "\($0) Days" }
                SlidingChipPicker([1, 3, 7], selection: $custom) { "\($0) Days" }
            }
            .padding()
            .background(Color.backgroundMain)
        }
    }

    return PreviewWrapper()
}
