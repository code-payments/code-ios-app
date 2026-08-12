//
//  OnrampVerificationIntroScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The combined explainer shown at the start of the on-ramp verification flow
/// (v2) when both phone and email verification are required. Ported from
/// Android's `VerificationIntroScreen`; "Next" advances to phone entry.
struct OnrampVerificationIntroScreen: View {

    let onNext: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(Color.textMain)

                Text("Verify Your Phone Number And Email To Continue")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Text("This will allow you to add funds from your debit card")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Spacer()

                Button("Next", action: onNext)
                    .buttonStyle(.filled)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
    }
}
