//
//  TrayOptionTile.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// One choice in a tray's grid of short options, such as preset amounts: a centred label on a
/// rounded tile, raised while selected.
///
/// Lay several out with ``TrayOptionTile/columns`` in a `LazyVGrid`. A tile behaves as
/// ``TrayOptionRow`` does: a selection snaps, and only the press moves.
public struct TrayOptionTile: View {

    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a tile; `isSelected` draws it raised.
    public init(_ title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: TrayMetrics.tileRadius, style: .continuous)
        Button(action: action) {
            Text(title)
                // SF Pro until type tokens are decided (Phase 2).
                .font(.system(size: TrayMetrics.scaled(TrayMetrics.rowTextSize, .body, dynamicTypeSize), weight: TrayMetrics.rowTextWeight))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected && TrayMetrics.tileSelection == .inverted ? Color.textAction : Color.textMain)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: TrayMetrics.tileHeight)
                .background(shape.fill(fill))
                .overlay {
                    if isSelected && TrayMetrics.tileSelection == .outline {
                        shape.strokeBorder(Color.textMain, lineWidth: 2)
                    }
                }
                .contentShape(shape)
                .animation(nil, value: isSelected)
        }
        .buttonStyle(TrayRowPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        guard isSelected else { return .white.opacity(TrayMetrics.rowFillOpacity) }
        switch TrayMetrics.tileSelection {
        case .raised: return .white.opacity(TrayMetrics.rowSelectedFillOpacity)
        case .outline: return .white.opacity(TrayMetrics.rowFillOpacity)
        case .inverted: return .action
        }
    }
}

extension TrayOptionTile {
    /// Three equal columns at the tray's row gap.
    @MainActor public static var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: TrayMetrics.rowGap), count: 3)
    }
}
