//
//  ModerationRequestTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("Moderation request construction")
struct ModerationRequestTests {

    @Test(
        "Each text kind is sent as its content kind",
        arguments: [
            (ModerationTextKind.currencyName, Flipcash_Moderation_V1_ContentKind.currencyName),
            (.currencySymbol, .currencySymbol),
            (.currencyDescription, .currencyDescription),
        ]
    )
    func textKind(kind: ModerationTextKind, expected: Flipcash_Moderation_V1_ContentKind) throws {
        let request = ModerationService.moderateTextRequest(
            "Jeffy",
            kind: kind,
            owner: try #require(KeyPair.generate())
        )

        #expect(request.text == "Jeffy")
        #expect(request.kind == expected)
        #expect(request.hasAuth)
    }

    @Test("The icon is sent as CURRENCY_ICON")
    func imageKind() throws {
        let request = ModerationService.moderateImageRequest(
            Data([0x89, 0x50, 0x4E, 0x47]),
            kind: .currencyIcon,
            owner: try #require(KeyPair.generate())
        )

        #expect(request.imageData == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(request.kind == .currencyIcon)
        #expect(request.hasAuth)
    }

    @Test("The text request's signature covers kind")
    func textSignatureCoversKind() throws {
        let owner = try #require(KeyPair.generate())
        let request = ModerationService.moderateTextRequest("Jeffy", kind: .currencyName, owner: owner)

        var signed = request
        signed.clearAuth()
        var withoutKind = signed
        withoutKind.kind = .unknownContentKind

        let signature = try Signature(request.auth.keyPair.signature.value)
        #expect(request.auth.keyPair.pubKey.value == owner.publicKey.data)
        #expect(owner.publicKey.verify(signature: signature, data: try signed.serializedData()))
        #expect(!owner.publicKey.verify(signature: signature, data: try withoutKind.serializedData()))
    }

    @Test("The image request's signature covers kind")
    func imageSignatureCoversKind() throws {
        let owner = try #require(KeyPair.generate())
        let request = ModerationService.moderateImageRequest(Data([0x01, 0x02]), kind: .currencyIcon, owner: owner)

        var signed = request
        signed.clearAuth()
        var withoutKind = signed
        withoutKind.kind = .unknownContentKind

        let signature = try Signature(request.auth.keyPair.signature.value)
        #expect(owner.publicKey.verify(signature: signature, data: try signed.serializedData()))
        #expect(!owner.publicKey.verify(signature: signature, data: try withoutKind.serializedData()))
    }
}
