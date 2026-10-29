//
//  PaymentRequestCardView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// The request card: "Request", the title, the progress line and bar, and the status line. `nil`
/// content draws the frame with placeholder lines while the request loads.
public struct PaymentRequestCard: View {

    let content: ChatPaymentRequestContent.Card?

    public init(content: ChatPaymentRequestContent.Card?) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Request")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)

            Text(content?.title ?? "Request title")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .lineLimit(2)

            Text(content?.progressLine ?? "$0 paid, $0 requested")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)

            PaymentRequestProgressBar(fraction: content?.fraction ?? 0, isEnded: content?.isEnded ?? false)

            Text(content?.statusLine ?? "0 days left to pay")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: content == nil ? .placeholder : [])
        .opacity(content?.isEnded == true ? 0.5 : 1)
        .requestMotion(value: content?.isEnded)
        .accessibilityElement(children: .combine)
    }
}

/// A capsule filled left to right with a request's paid fraction.
public struct PaymentRequestProgressBar: View {

    let fraction: Double
    let isEnded: Bool

    public init(fraction: Double, isEnded: Bool) {
        self.fraction = fraction
        self.isEnded = isEnded
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.textMain.opacity(0.15))
                Capsule()
                    .fill(isEnded ? Color.textSecondary : Color.success)
                    .frame(width: proxy.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
        .requestMotion(value: fraction)
        .requestMotion(value: isEnded)
        .accessibilityHidden(true)
    }
}
