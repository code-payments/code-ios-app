//
//  ChatPhotoSendTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import SharedCore
import Testing
@testable import FlipcashCore

@Suite("Chat photo send")
struct ChatPhotoSendTests {

    private static func seal() throws -> ChatSeal {
        try ChatSeal(
            cipher: DefaultChatCipher.shared,
            owner: KeyPair.generate()!,
            peerPublicKey: KeyPair.generate()!.publicKey,
            conversationID: ConversationID(data: Data(repeating: 0x07, count: 32)),
            selfUserID: UUID()
        )
    }

    @Test("A refused photo reports as an expected outcome, a client defect as an error")
    func reportingLevels() {
        #expect(ChatMediaUploadError.rejected(.moderation).reportingLevel == .info)
        #expect(ChatMediaUploadError.noMatchingConstraint.reportingLevel == .error)
        #expect(ChatMediaUploadError.failed(ErrorBlob.quotaExceeded).reportingLevel == .info)
        #expect(ChatMediaUploadError.failed(ErrorBlob.unknown).reportingLevel == .error)
    }

    @Test("A photo goes out only under the encryption choice it was uploaded for")
    func photoSendMatchesSeal() throws {
        let seal = try Self.seal()
        let chat = seal.conversationID
        let other = ConversationID(data: Data(repeating: 0x08, count: 32))
        let blobID = BlobID(data: Data([1]))
        let sealed = SealedPhoto(blobID: blobID, mimeType: "image/jpeg", sizeBytes: 10, width: 1, height: 1, blurhash: "00")

        #expect(ChatPhotoSend.matching(.plain(blobID), seal: nil, conversationID: chat) == .plain(blobID))
        #expect(ChatPhotoSend.matching(.sealed(sealed), seal: seal, conversationID: chat) == .sealed(sealed, seal))
        // The chat started encrypting after the photo uploaded in plaintext.
        #expect(ChatPhotoSend.matching(.plain(blobID), seal: seal, conversationID: chat) == .mismatch)
        // The chat stopped encrypting after the photo uploaded sealed.
        #expect(ChatPhotoSend.matching(.sealed(sealed), seal: nil, conversationID: chat) == .mismatch)
        // A seal for a different chat.
        #expect(ChatPhotoSend.matching(.sealed(sealed), seal: seal, conversationID: other) == .mismatch)
    }
}
