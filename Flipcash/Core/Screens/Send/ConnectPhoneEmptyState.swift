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
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(.Icons.send)
                    .foregroundStyle(Color.textSecondary)
                Text("Connect Phone To Send")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                Text("Connect your phone number to send cash")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Connect Your Phone Number", action: onConnect)
                .buttonStyle(.filled)
        }
        .padding(20)
    }
}

// MARK: - Previews -

#Preview {
    ConnectPhoneEmptyState(onConnect: {})
}
