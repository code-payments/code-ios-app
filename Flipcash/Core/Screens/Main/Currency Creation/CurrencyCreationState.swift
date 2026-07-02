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
}
