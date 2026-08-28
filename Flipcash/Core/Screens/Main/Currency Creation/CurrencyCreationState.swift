//
//  CurrencyCreationState.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

// MARK: - CreationProgressBar

struct CreationProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        ProgressView(value: Double(current), total: Double(total))
            .progressViewStyle(.linear)
            .tint(Color.textMain)
            .frame(width: 140)
    }
}

// MARK: - CurrencyCreationState

@Observable
final class CurrencyCreationState {

    /// A step of the creation wizard. Lives on the draft rather than in the
    /// wizard's `@State` so backing out and re-entering resumes where the user
    /// left off instead of replaying the moderation calls from the name step.
    enum Step: Int, CaseIterable {
        case name = 0, icon, description, billCreation, confirmation, paymentSelection

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }

        /// Whether this step joins the progress bar. The payment picker shows a
        /// title instead, so it opts out — the bar's total derives from this, not
        /// a hard-coded count.
        var showsProgressBar: Bool { self != .paymentSelection }

        /// Number of steps the progress bar counts.
        static let progressStepCount = allCases.filter(\.showsProgressBar).count
    }

    /// The step the wizard is showing.
    var step: Step = .name

    /// UI clamp and validator bound for the description. The server allows
    /// 4096; 500 is the product choice.
    static let descriptionCharLimit = 500

    var currencyName: String = "" {
        didSet { if currencyName != oldValue { nameAttestation = nil } }
    }
    var selectedImage: UIImage? {
        didSet {
            if selectedImage !== oldValue {
                iconAttestation = nil
                encodedIconData = nil
            }
        }
    }
    var currencyDescription: String = "" {
        didSet { if currencyDescription != oldValue { descriptionAttestation = nil } }
    }
    var backgroundColors: [Color] = ColorEditorControl.randomDerivedColors()

    // Attestations (cleared by the setters above when the corresponding field changes)
    var nameAttestation: ModerationAttestation?
    var iconAttestation: ModerationAttestation?
    var descriptionAttestation: ModerationAttestation?

    /// JPEG-encoded icon data produced by ImageEncoder.encodeForUpload (<= 1 MB).
    /// Populated on successful icon-step moderation, reused by Launch. Cleared
    /// when the user changes the selected image.
    var encodedIconData: Data?

    @ObservationIgnored private let nameValidator = CurrencyNameValidator()
    @ObservationIgnored private let descriptionValidator = LengthValidator(maxLength: CurrencyCreationState.descriptionCharLimit)

    /// The name accepted by the Launch RPC's contract, or nil while the
    /// current input is invalid. This exact string flows to availability,
    /// moderation, and launch.
    var validatedCurrencyName: String? {
        nameValidator.validate(currencyName)
    }

    var isCurrencyNameValid: Bool {
        validatedCurrencyName != nil
    }

    var isCurrencyDescriptionValid: Bool {
        descriptionValidator.validate(currencyDescription) != nil
    }

    /// Returns the draft to a blank first-run state. Called when a new creation
    /// starts, so a finished or abandoned attempt doesn't prefill the next one.
    /// The attestations are cleared explicitly: the field setters only clear
    /// them on a *change*, and a field that is already empty doesn't change.
    func reset() {
        currencyName = ""
        selectedImage = nil
        currencyDescription = ""
        backgroundColors = ColorEditorControl.randomDerivedColors()
        nameAttestation = nil
        iconAttestation = nil
        descriptionAttestation = nil
        encodedIconData = nil
        step = .name
    }
}
