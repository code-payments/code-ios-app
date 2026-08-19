//
//  TokenCardView.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// One token's data for a ``TokenCardView`` / ``TokenCardStack``.
struct TokenCardData: Identifiable, Equatable {
    let mint: PublicKey
    let name: String
    let imageURL: URL?
    let balanceText: String
    /// Signed appreciation, already formatted (e.g. "+$2.84"); nil hides the pill.
    let appreciationText: String?
    /// The token's bill-customization colors (`#RRGGBB`). Empty → dark-green fallback.
    let colors: [String]
    let isUSDF: Bool

    var id: PublicKey { mint }
}

/// A reusable bill-style card for a single token (Figma frame 8966:99811, ported
/// from Android's `TokenCard`). The background is a horizontal gradient painted
/// from the token's bill-customization colors — the same palette users pick in
/// the currency creator — with USDF's fixed gold branding and a dark-green
/// fallback for tokens with no customization. The header shows the token icon +
/// name (leading) and an optional appreciation pill + balance (trailing).
///
/// These stack: render several with a negative vertical spacing so only each
/// card's header shows, like ``TokenCardStack``.
struct TokenCardView: View {

    let name: String
    let imageURL: URL?
    let balanceText: String
    /// Signed appreciation, already formatted (e.g. "+$2.84"); nil hides the pill.
    let appreciationText: String?
    /// The token's bill-customization colors (`#RRGGBB`). Empty → dark-green fallback.
    let colors: [String]
    let isUSDF: Bool

    var height: CGFloat = 224

    init(name: String, imageURL: URL?, balanceText: String, appreciationText: String?, colors: [String], isUSDF: Bool, height: CGFloat = 224) {
        self.name = name
        self.imageURL = imageURL
        self.balanceText = balanceText
        self.appreciationText = appreciationText
        self.colors = colors
        self.isUSDF = isUSDF
        self.height = height
    }

    init(data: TokenCardData, height: CGFloat = 224) {
        self.init(
            name: data.name,
            imageURL: data.imageURL,
            balanceText: data.balanceText,
            appreciationText: data.appreciationText,
            colors: data.colors,
            isUSDF: data.isUSDF,
            height: height
        )
    }

    private static let cornerRadius: CGFloat = Metrics.boxRadius   // 12 — medium shape
    private static let fallback = Color(hex: "#06450F")!
    private static let usdfGradient = [Color(hex: "#C4980B")!, Color(hex: "#B06B00")!]

    private var gradient: LinearGradient {
        let stops: [Color]
        if isUSDF {
            stops = Self.usdfGradient
        } else {
            let parsed = colors.compactMap(Color.init(hex:))
            switch parsed.count {
            case 0:  stops = [Self.fallback, Self.fallback]
            case 1:  stops = [parsed[0], parsed[0]]
            default: stops = parsed
            }
        }
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(gradient)
            .overlay(alignment: .trailing) {
                if isUSDF { dollarWatermark }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .overlay(alignment: .top) { header.padding(16) }
    }

    /// The Dollars bill's oversized "$", vertically centred and tucked toward the
    /// right edge — taller than the card so it clips top and bottom. White at 30%
    /// over an overlay blend, matching the Figma watermark (node 9223:23556).
    private var dollarWatermark: some View {
        Text("$")
            .font(.default(size: 213, weight: .bold))
            .foregroundStyle(.white)
            .opacity(0.30)
            .blendMode(.overlay)
            .fixedSize()
            .padding(.trailing, 10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let imageURL {
                RemoteImage(url: imageURL)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            }
            Text(name)
                .font(.appTextSmall)
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let appreciationText {
                Text(appreciationText)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 1)
                    )
                    .layoutPriority(1)
            }

            Text(balanceText)
                .font(.appDisplaySmall)
                .fontWeight(.bold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Previews -

#Preview("Token cards") {
    VStack(spacing: 16) {
        // USDF: gold branding + the oversized "$" watermark.
        TokenCardView(
            name: "Dollars",
            imageURL: nil,
            balanceText: "$205.94",
            appreciationText: "+$0.00",
            colors: [],
            isUSDF: true
        )
        // Bonded token: gradient painted from its bill-customization colors.
        TokenCardView(
            name: "Jeffy",
            imageURL: nil,
            balanceText: "$121.74",
            appreciationText: "-$21.35",
            colors: ["#F5B301", "#B06B00"],
            isUSDF: false
        )
        // No customization → dark-green fallback, no appreciation pill.
        TokenCardView(
            name: "Testament",
            imageURL: nil,
            balanceText: "$10.00",
            appreciationText: nil,
            colors: [],
            isUSDF: false
        )
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.backgroundMain)
}
