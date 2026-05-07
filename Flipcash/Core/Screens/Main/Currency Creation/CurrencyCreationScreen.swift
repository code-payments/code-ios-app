//
//  CurrencyCreationScreen.swift
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

// MARK: - CurrencyCreationStep

enum CurrencyCreationStep: Hashable {
    case summary
    case wizard
}

// MARK: - CurrencyCreationState

@Observable
final class CurrencyCreationState {
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

    /// True when the current name passes both the char-range check and the
    /// printable-ASCII pattern enforced by the server's Launch RPC:
    /// `^[!-~]([ -~]*[!-~])?$` — no leading or trailing space, 1-32 chars.
    var isCurrencyNameValid: Bool {
        guard !currencyName.isEmpty, currencyName.count <= 32 else { return false }
        return currencyName.wholeMatch(of: currencyNameAllowedPattern) != nil
    }
}

/// Matches server validation pattern `^[!-~]([ -~]*[!-~])?$`:
/// printable ASCII, no leading or trailing space, 1+ chars.
private let currencyNameAllowedPattern = #/^[!-~]([ -~]*[!-~])?$/#

// MARK: - CurrencyCreationFlow

