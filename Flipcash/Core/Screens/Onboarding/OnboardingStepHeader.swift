//
//  OnboardingStepHeader.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Spacing shared by the Group Money onboarding steps (frames 2-03 to 2-06), so phone, code,
/// email and name keep one left edge and put the title, subtitle and form at the same heights.
///
/// The frames set their text in SF, whose line box is shorter than Avenir's, so these gaps are
/// tuned to where the frames' glyphs sit, not copied from the frames' box gaps.
enum OnboardingStepMetrics {
    /// The left and right edge of everything on the step, the button included.
    static let edge: CGFloat = 24
    /// Title to subtitle.
    static let titleToSubtitle: CGFloat = 26
    /// The subtitle's two lines to the first row of the form.
    static let headerToForm: CGFloat = 20
    /// Between rows of the form: a field and the paragraph under it, or the code boxes, the
    /// resend row and the explanation.
    static let formSpacing: CGFloat = 24
    /// A field's label to the field.
    static let labelToField: CGFloat = 10
}

/// A Group Money onboarding step: the header, the form under it, and the step's action at the
/// bottom.
struct OnboardingStepLayout<Form: View, Action: View>: View {

    let header: StepHeaderText
    @ViewBuilder let form: Form
    @ViewBuilder let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepHeader(text: header)

            form
                .padding(.top, OnboardingStepMetrics.headerToForm)

            Spacer(minLength: 0)

            action
        }
        .padding(.horizontal, OnboardingStepMetrics.edge)
        .padding(.top, 20)
        .bottomEdgePadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The title and subtitle at the top of a Group Money onboarding step (frames 2-03 to 2-06).
struct OnboardingStepHeader: View {

    let text: StepHeaderText

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingStepMetrics.titleToSubtitle) {
            Text(text.title)
                .font(.appDisplayCompact)
                .foregroundStyle(Color.textMain)
                .accessibilityAddTraits(.isHeader)
            Text(text.subtitle)
                .font(.appTextBody)
                .foregroundStyle(Color.textSecondary)
                // A one-line subtitle still holds two lines, so the form starts at the same
                // height on every step, as in the frames.
                .lineLimit(2...)
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
