//
//  SendBackSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// Resets the swipe knob without its checkmark: the sheet closes on the swipe and the row, not the
/// sheet, shows how the return goes.
private struct SendBackSheetDismissed: Error {}

/// Confirms sending a DM's opening payment back: the amount, the currency it goes back in, who gets
/// it, and a swipe. Nothing here can be changed — the return is the original's amount, in its
/// currency, to its sender — so the currency is a label, not a picker (design node 13296:557).
struct SendBackSheet: View {

    @Environment(\.dismiss) private var dismiss

    let offer: SendBackOffer
    /// The swipe. Returns once the return is submitting or was blocked; the sheet closes either way.
    let onSwipe: (SendBackOffer) async -> Void

    var body: some View {
        PartialSheet(background: .clear) {
            VStack(spacing: 25) {
                VStack(spacing: 12) {
                    Text(offer.original.nativeAmount.formatted())
                        .font(.appDisplayLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    CurrencyLabel(imageURL: offer.iconURL, name: offer.token, amount: nil)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .strokeBorder(
                                    Metrics.inputFieldStrokeColor(highlighted: false),
                                    lineWidth: Metrics.inputFieldBorderWidth(highlighted: false)
                                )
                        }

                    Text("Send back to \(offer.recipientName)")
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                SwipeControl(text: "Swipe to Send Back") {
                    await onSwipe(offer)
                    dismiss()
                    throw SendBackSheetDismissed()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
    }

    /// The design's 20 under the swipe, less whatever the sheet already holds back for the home
    /// indicator — stacking the two doubles the gap. As ``StartChattingSheet``.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}
