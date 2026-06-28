//
//  ConnectPhoneEmptyState.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Empty state shown when the user opens the Send sheet without a verified
/// phone number. A ghosted cash-card-and-chat illustration sells the feature and
/// the primary CTA launches the standalone phone verification flow. Rendered in
/// the non-searchable stack; the "Send" title and close button come from the
/// hosting `NavigationStack`.
struct ConnectPhoneEmptyState: View {

    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            SendConversationHero()

            VStack(spacing: 8) {
                Text("Send Money To Your Friends")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                Text("Send money to friends as easily as a text. Connect your phone number to get started.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            Spacer(minLength: 0)

            Button("Next", action: onConnect)
                .buttonStyle(.filled)
        }
        .padding(20)
    }
}

// MARK: - Previews -

#Preview {
    NavigationStack {
        ConnectPhoneEmptyState(onConnect: {})
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.backgroundMain)
            .navigationTitle("Send")
            .toolbarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}
