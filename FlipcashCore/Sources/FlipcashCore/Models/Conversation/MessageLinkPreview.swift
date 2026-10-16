//
//  MessageLinkPreview.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A preview of a link in a text message, built by the sending device from the page and carried
/// in the message (`messaging.v1.LinkPreview`). Recipients draw it as sent and never fetch the page.
public struct MessageLinkPreview: Hashable, Sendable, Codable {

    /// The link the preview describes, exactly as it appears in the message text.
    public let url: String

    /// The page's title, as the sender cleaned it.
    public let title: String

    /// The page's description, or `nil` when it has none.
    public let description: String?

    /// The page's image, uploaded like a chat photo, or `nil` when it has none.
    public let image: MediaAttachment?

    public init(url: String, title: String, description: String?, image: MediaAttachment?) {
        self.url = url
        self.title = title
        self.description = description
        self.image = image
    }

    /// This preview when its url is still a whole link in `text`, otherwise `nil`.
    public func kept(for text: String) -> MessageLinkPreview? {
        LinkPreviewSendChecks.isWholeLink(url: url, in: text) ? self : nil
    }
}

// MARK: - Proto -

extension MessageLinkPreview {

    /// The wire preview, for a message sent sealed when `sealed` is true. An image uploaded for the
    /// other mode is left off: a sealed message references only an encrypted blob and a plaintext
    /// message only one the server can moderate.
    func proto(sealed: Bool) -> Flipcash_Messaging_V1_LinkPreview {
        .with {
            $0.url = url
            $0.title = title
            $0.description_p = description ?? ""
            if let media = image.flatMap({ Self.media(for: $0, sealed: sealed) }) {
                $0.image = media
            }
        }
    }

    private static func media(for image: MediaAttachment, sealed: Bool) -> Flipcash_Blob_V1_Media? {
        guard let blobID = image.blobID else { return nil }
        switch (sealed, image.sealed) {
        case (true, let blob?):
            return SealedPhoto(
                blobID: blobID,
                mimeType: ChatMediaEncoder.mimeType,
                sizeBytes: blob.plaintextSize,
                width: image.width,
                height: image.height,
                blurhash: image.blurhash ?? ""
            ).media
        case (false, nil):
            return image.proto
        case (true, nil), (false, _?):
            return nil
        }
    }

    /// The preview `proto` carries for `text`, or `nil` when it breaks the contract: its url is not
    /// a whole link in `text`, or its title has nothing visible. A sealed preview passes `senderID`,
    /// whose image metadata is the sender's and is checked like encrypted media; an image that fails
    /// is dropped and the preview kept.
    init?(_ proto: Flipcash_Messaging_V1_LinkPreview, text: String, sealedBy senderID: UserID? = nil) {
        guard LinkPreviewSendChecks.isWholeLink(url: proto.url, in: text),
              LinkPreviewSendChecks.cleanTitle(proto.title) != nil else { return nil }
        let image: MediaAttachment?
        if !proto.hasImage {
            image = nil
        } else if let senderID {
            image = MediaAttachment(sealed: proto.image, senderID: senderID)
        } else {
            image = MediaAttachment(proto.image)
        }
        self.init(
            url: proto.url,
            title: proto.title,
            description: proto.description_p.isEmpty ? nil : proto.description_p,
            image: image
        )
    }

    /// The first preview `text` carries, the one this client renders.
    static func first(of text: Flipcash_Messaging_V1_TextContent, sealedBy senderID: UserID? = nil) -> MessageLinkPreview? {
        text.linkPreviews.first.flatMap { MessageLinkPreview($0, text: text.text, sealedBy: senderID) }
    }
}
