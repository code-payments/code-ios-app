//
//  MarketCapExplainerRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The entry row under the market cap chart (Figma node 10761:1879).
struct MarketCapExplainerRow: View {
    let tokenName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MarketCapCurveIcon()
                    .frame(width: 22, height: 22)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.rowSeparator))

                VStack(alignment: .leading, spacing: 2) {
                    Text("How \(tokenName)'s Price Works")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text("See what moves market cap · 1 min")
                        .font(.default(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 12, height: 12)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.backgroundRow)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The rising-curve glyph, drawn on a 22×22 grid: a stroked line ending in a dot.
private struct MarketCapCurveIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 22
            var line = Path()
            line.move(to: CGPoint(x: 2.75 * scale, y: 17.4167 * scale))
            line.addCurve(
                to: CGPoint(x: 19.25 * scale, y: 4.58333 * scale),
                control1: CGPoint(x: 9.16667 * scale, y: 17.4167 * scale),
                control2: CGPoint(x: 13.75 * scale, y: 14.6667 * scale)
            )
            context.stroke(
                line,
                with: .color(Color.Sentiment.positive),
                style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round, lineJoin: .round)
            )
            let r = 1.65 * scale
            context.fill(
                Path(ellipseIn: CGRect(x: 19.25 * scale - r, y: 4.58333 * scale - r, width: r * 2, height: r * 2)),
                with: .color(Color.Sentiment.positive)
            )
        }
    }
}
