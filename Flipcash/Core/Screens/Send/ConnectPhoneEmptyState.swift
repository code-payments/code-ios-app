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
            VStack(spacing: 20) {
                Spacer()
                Image(.Icons.send)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Connect Phone To Send")
                    .font(.appTitle)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                Text("Connect your phone number to send cash")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Spacer()
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
