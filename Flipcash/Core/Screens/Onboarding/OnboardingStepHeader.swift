//
//  OnboardingStepHeader.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The title and subtitle at the top of a Group Money onboarding step (frames 2-03 to 2-06).
struct OnboardingStepHeader: View {

    let text: StepHeaderText

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title)
                .font(.appDisplayCompact)
                .foregroundStyle(Color.textMain)
                .accessibilityAddTraits(.isHeader)
            Text(text.subtitle)
                .font(.appTextBody)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The label above a field on a Group Money onboarding step.
struct OnboardingFieldLabel: View {

    let title: String

    var body: some View {
        Text(title)
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
