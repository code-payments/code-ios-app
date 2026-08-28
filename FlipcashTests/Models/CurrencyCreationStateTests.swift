//
//  CurrencyCreationStateTests.swift
//  FlipcashTests
//

import Testing
import UIKit
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("CurrencyCreationState")
struct CurrencyCreationStateTests {

    // MARK: - Validation routing

    @Test("valid name passes and surfaces the validated form")
    func validName_passesValidation() {
        let state = CurrencyCreationState()
        state.currencyName = "My Coin"
        #expect(state.isCurrencyNameValid)
        #expect(state.validatedCurrencyName == "My Coin")
    }

    @Test("invalid name fails and yields no validated form")
    func invalidName_failsValidation() {
        let state = CurrencyCreationState()
        state.currencyName = " Coin"
        #expect(state.isCurrencyNameValid == false)
        #expect(state.validatedCurrencyName == nil)
    }

    @Test("non-blank description within the limit is valid")
    func description_withinLimit_valid() {
        let state = CurrencyCreationState()
        state.currencyDescription = "A coin for testing"
        #expect(state.isCurrencyDescriptionValid)
    }

    @Test("description over the limit is invalid")
    func overlongDescription_invalid() {
        let state = CurrencyCreationState()
        state.currencyDescription = String(repeating: "x", count: CurrencyCreationState.descriptionCharLimit + 1)
        #expect(state.isCurrencyDescriptionValid == false)
    }

    // MARK: - Attestation invalidation on field edit

    @Test("changing currencyName clears nameAttestation")
    func changingName_clearsNameAttestation() {
        let state = CurrencyCreationState()
        state.currencyName = "OriginalName"
        state.nameAttestation = ModerationAttestation(rawValue: Data([0x01]))

        state.currencyName = "DifferentName"

        #expect(state.nameAttestation == nil)
    }

    @Test("re-setting same currencyName keeps nameAttestation")
    func sameName_keepsNameAttestation() {
        let state = CurrencyCreationState()
        state.currencyName = "SameName"
        state.nameAttestation = ModerationAttestation(rawValue: Data([0x01]))

        state.currencyName = "SameName"

        #expect(state.nameAttestation != nil)
    }

    @Test("changing selectedImage clears iconAttestation and encodedIconData")
    func changingImage_clearsIconState() {
        let state = CurrencyCreationState()
        let firstImage = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
            .image { _ in }
        let secondImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
            .image { _ in }

        state.selectedImage = firstImage
        state.iconAttestation = ModerationAttestation(rawValue: Data([0x02]))
        state.encodedIconData = Data([0xAB, 0xCD])

        state.selectedImage = secondImage

        #expect(state.iconAttestation == nil)
        #expect(state.encodedIconData == nil)
    }

    @Test("changing currencyDescription clears descriptionAttestation")
    func changingDescription_clearsDescriptionAttestation() {
        let state = CurrencyCreationState()
        state.currencyDescription = "original"
        state.descriptionAttestation = ModerationAttestation(rawValue: Data([0x03]))

        state.currencyDescription = "different"

        #expect(state.descriptionAttestation == nil)
    }

    // MARK: - Draft lifetime

    // The draft is session-scoped so popping the wizard — an edge swipe, the
    // toolbar chevron — no longer discards what the user entered. That makes
    // `reset()` the only thing standing between one attempt and the next.

    @Test("reset clears every field a previous attempt could have filled")
    func reset_clearsFilledDraft() {
        let state = CurrencyCreationState()
        state.currencyName = "MyCoin"
        state.currencyDescription = "A coin"
        state.step = .confirmation
        state.nameAttestation = ModerationAttestation(rawValue: Data([0x01]))
        state.encodedIconData = Data([0x02])

        state.reset()

        #expect(state.currencyName == "")
        #expect(state.currencyDescription == "")
        #expect(state.step == .name)
        #expect(state.nameAttestation == nil)
        #expect(state.encodedIconData == nil)
    }

    /// The field setters clear their attestation on a *change*. A draft whose
    /// text is already empty doesn't change, so reset has to clear the
    /// attestations itself or a stale proof outlives the input it attests to.
    @Test("reset clears attestations even when the fields are already empty")
    func reset_clearsAttestationsWithoutFieldChanges() {
        let state = CurrencyCreationState()
        state.nameAttestation = ModerationAttestation(rawValue: Data([0x01]))
        state.iconAttestation = ModerationAttestation(rawValue: Data([0x02]))
        state.descriptionAttestation = ModerationAttestation(rawValue: Data([0x03]))

        state.reset()

        #expect(state.nameAttestation == nil)
        #expect(state.iconAttestation == nil)
        #expect(state.descriptionAttestation == nil)
    }

    // MARK: - Wizard steps

    @Test("steps walk to the ends of the wizard and stop")
    func step_boundaries() {
        #expect(CurrencyCreationState.Step.name.previous == nil)
        #expect(CurrencyCreationState.Step.paymentSelection.next == nil)
        #expect(CurrencyCreationState.Step.name.next == .icon)
        #expect(CurrencyCreationState.Step.icon.previous == .name)
    }

    /// The payment picker titles itself instead of joining the bar.
    @Test("the progress bar counts every step but the payment picker")
    func step_progressStepCount() {
        #expect(
            CurrencyCreationState.Step.progressStepCount
                == CurrencyCreationState.Step.allCases.count - 1
        )
        #expect(!CurrencyCreationState.Step.paymentSelection.showsProgressBar)
    }
}
