//
//  PhoneVerificationCopy.swift
//  Flipcash
//

import Foundation

/// The words on ``EnterPhoneScreen`` and ``ConfirmPhoneScreen``.
///
/// ``standard`` is what the on-ramp shows, with the screen titled by its host. ``onboarding`` is
/// the Group Money new-account flow (frames node 2-03 and 2-04): a title and subtitle drawn at
/// the top of each screen, a label over the phone field, and shorter resend text.
enum PhoneVerificationCopy: Equatable {
    case standard
    case onboarding

    // MARK: - Phone entry -

    /// The title and subtitle at the top of the phone entry screen, or nil when the host titles it.
    var entryHeader: StepHeaderText? {
        switch self {
        case .standard:
            nil
        case .onboarding:
            StepHeaderText(
                title: "Your phone number",
                subtitle: "Enter your phone number to create your account."
            )
        }
    }

    /// The label above the phone field, or nil for none.
    var entryFieldLabel: String? {
        switch self {
        case .standard:   nil
        case .onboarding: "Phone number"
        }
    }

    /// The line under the phone field while the number is not known to be invalid.
    var entryHint: String {
        switch self {
        case .standard:   "Please enter your phone number to continue"
        case .onboarding: "We'll text you a verification code."
        }
    }

    // MARK: - Code entry -

    /// The title and subtitle at the top of the code screen, or nil when the host titles it.
    ///
    /// - Parameters:
    ///   - phone: the number the code went to, as shown to the user.
    ///   - digits: how many digits the code has.
    func codeHeader(phone: String, digits: Int) -> StepHeaderText? {
        switch self {
        case .standard:
            nil
        case .onboarding:
            StepHeaderText(
                title: "Enter verification code",
                subtitle: "Enter the \(digits)-digit code we sent to \(phone)."
            )
        }
    }

    /// The paragraph under the code boxes.
    var codeExplanation: String {
        switch self {
        case .standard:   "An SMS message was sent to your phone number with a verification code. Please enter the verification code above."
        case .onboarding: "This confirms that this number belongs to you."
        }
    }

    /// The resend button's title once a new code can be requested.
    var resendTitle: String {
        switch self {
        case .standard:   "Didn't get an SMS? Resend"
        case .onboarding: "Resend code"
        }
    }
}

/// A screen's title and the sentence under it.
struct StepHeaderText: Equatable {
    let title: String
    let subtitle: String
}
