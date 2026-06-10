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
}
