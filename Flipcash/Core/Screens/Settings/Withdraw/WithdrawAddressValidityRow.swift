//
//  WithdrawAddressValidityRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawAddressValidityRow: View {
    let metadata: DestinationMetadata
    let acceptsTokenAccount: Bool

    var body: some View {
        if shouldRenderInvalid {
            InvalidAddressRow()
        } else {
            ValidAddressRow()
        }
    }

    private var shouldRenderInvalid: Bool {
        switch metadata.kind {
        case .unknown:
            return true
        case .token:
            return !acceptsTokenAccount
        case .owner:
            return false
        }
    }
}

private struct InvalidAddressRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image.system(.xmark)
            Text("Destination address not valid")
                .lineLimit(1)
        }
        .font(.appTextHeading)
        .foregroundStyle(Color.textError)
    }
}

private struct ValidAddressRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Image.system(.circleCheck)
            Text("Valid address")
                .lineLimit(1)
        }
        .font(.appTextHeading)
        .foregroundStyle(Color.textSuccess)
    }
}
