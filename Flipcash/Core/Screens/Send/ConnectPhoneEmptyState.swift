//
//  ConnectPhoneEmptyState.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Empty state shown when the user opens the Send sheet without a verified
/// phone number. Primary CTA launches the standalone phone verification flow.
struct ConnectPhoneEmptyState: View {

    let onConnect: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Connect Phone To Send")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
            } icon: {
                Image(.Icons.send)
            }
        } description: {
            Text("Connect your phone number to send cash")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        } actions: {
            Button("Connect Your Phone Number", action: onConnect)
                .buttonStyle(.filled)
        }
    }
}

// MARK: - Previews -

#Preview {
    ConnectPhoneEmptyState(onConnect: {})
}
