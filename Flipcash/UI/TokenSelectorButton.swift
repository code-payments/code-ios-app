//
//  TokenSelectorButton.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// The selected-currency affordance shared by the amount-entry surfaces: the
/// currency's image and name with a disclosure chevron, opening the
/// held-currency picker. A collection's pay sheet hides the chevron.
struct TokenSelectorButton: View {

    let selectedBalance: ExchangedBalance?
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                CurrencyLabel(
                    imageURL: selectedBalance?.stored.imageURL,
                    name: selectedBalance?.stored.name ?? "",
                    amount: nil
                )

                if showsChevron {
                    Image.icon(.chevronDownMedium)
                        .iconSize(16)
                        .foregroundStyle(.textMain)
                }
            }
        }
    }
}

/// Draws the token selector as a filled chip with the house press, for a surface with no toolbar
/// around it to say the currency can be changed.
struct TokenChipStyle: ButtonStyle {

    /// The chip's fixed height, for a surface sized to a frame; nil pads the label 10 above and below.
    var height: CGFloat? = nil
    var horizontalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, height == nil ? 10 : 0)
            .frame(height: height)
            .background(Color.actionSecondary, in: Capsule())
            // Under 44 pt tall, so the hit area keeps the chip's corners.
            .contentShape(.rect)
            .buttonPress(isPressed: configuration.isPressed)
    }
}
