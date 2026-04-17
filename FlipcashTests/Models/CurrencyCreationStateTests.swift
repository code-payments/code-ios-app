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

    // MARK: - isCurrencyNameValid

    @Test("empty name is invalid")
    func emptyName_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = ""
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("single printable ASCII char is valid")
    func singleChar_valid() {
        let state = CurrencyCreationState()
        state.currencyName = "A"
        #expect(state.isCurrencyNameValid == true)
    }

    @Test("exactly 32 chars is valid")
    func thirtyTwoChars_valid() {
        let state = CurrencyCreationState()
        state.currencyName = String(repeating: "A", count: 32)
        #expect(state.isCurrencyNameValid == true)
    }

    @Test("more than 32 chars is invalid")
    func moreThan32Chars_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = String(repeating: "A", count: 33)
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("name with internal space is valid")
    func internalSpace_valid() {
        let state = CurrencyCreationState()
        state.currencyName = "My Coin"
        #expect(state.isCurrencyNameValid == true)
    }

    @Test("leading space is invalid")
    func leadingSpace_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = " Coin"
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("trailing space is invalid")
    func trailingSpace_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = "Coin "
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("whitespace-only is invalid")
    func whitespaceOnly_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = "   "
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("non-ASCII characters are invalid")
    func nonASCII_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = "café"
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("emoji is invalid")
    func emoji_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = "Coin🎉"
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("newline is invalid")
    func newline_invalid() {
        let state = CurrencyCreationState()
        state.currencyName = "Co\nin"
        #expect(state.isCurrencyNameValid == false)
    }

    @Test("printable ASCII punctuation is valid")
    func printableAsciiPunctuation_valid() {
        let state = CurrencyCreationState()
        state.currencyName = "Coin!$#@"
        #expect(state.isCurrencyNameValid == true)
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
