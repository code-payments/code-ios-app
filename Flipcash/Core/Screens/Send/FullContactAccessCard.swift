//
//  FullContactAccessCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Prompt shown atop the recipient list in iOS 18 limited access, nudging the
/// user to Settings to share their full address book so they can send cash and
/// recognize people they know. Dismissible — the caller owns the persisted
/// dismissal so it never reappears once closed.
struct FullContactAccessCard: View {

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image.asset(.exclamationTriangle)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Full Contact Access")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text("Make sure you can send cash and identify people you know")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            Button("Settings") {
                URL.openSettings()
            }
            .buttonStyle(.filled20Compact)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.backgroundSecondary)
        }
    }
}

#Preview {
    FullContactAccessCard(onDismiss: {})
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
}
