//
//  TipCardDownloadSheet.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashUI

/// The file format the user picked to export their tip card as (Figma node
/// 9278:7126).
enum TipCardDownloadFormat: String, Identifiable, CaseIterable {
    case png
    case svg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .svg: "SVG"
        }
    }

    /// The one-line pitch shown under the title, naming what the format is good for.
    var subtitle: String {
        switch self {
        case .png: "Social, chats, overlays"
        case .svg: "Stays sharp at any size"
        }
    }

    var asset: Asset {
        switch self {
        case .png: .fileBend
        case .svg: .bezierCurve
        }
    }
}

/// The "Download As" bottom sheet: one row per ``TipCardDownloadFormat``, plus
/// a Cancel row. Presented from the You tab's Download button.
///
/// Takes only a selection handler — it neither renders nor writes the file, so
/// the caller owns what a chosen format actually produces.
struct TipCardDownloadSheet: View {

    let onSelect: (TipCardDownloadFormat) -> Void
    let onCancel: VoidAction

    var body: some View {
        PartialSheet(background: .backgroundSecondary) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Download As")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    ForEach(TipCardDownloadFormat.allCases) { format in
                        Button {
                            onSelect(format)
                        } label: {
                            formatRow(format)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("you-download-\(format.rawValue)")
                    }

                    Button("Cancel", action: onCancel)
                        .buttonStyle(.textLink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
    }

    /// The design's 16 under Cancel, less whatever the sheet already holds back
    /// for the home indicator: stacking the two is what left the sheet with
    /// roughly three times the design's gap. Only devices with no indicator to
    /// clear pay the full 16 here — the rest already have more than that.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }

    private func formatRow(_ format: TipCardDownloadFormat) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(format.title)
                    .font(.appTextMedium)
                Text(format.subtitle)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.downloadSheetSecondaryText)
            }
            .foregroundStyle(Color.textMain)

            Spacer(minLength: 0)

            Image.asset(format.asset)
                .renderingMode(.template)
                .foregroundStyle(Color.textMain)
                .frame(width: 32, height: 32)
        }
        .padding(16)
        .background(Color.fillControl, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }
}

private extension Color {
    /// The sheet's quieter text: white 50% in dark, black 60% in light, where 50% falls short of AA.
    static let downloadSheetSecondaryText = Color(light: .black.opacity(0.6), dark: .white.opacity(0.5))
}
