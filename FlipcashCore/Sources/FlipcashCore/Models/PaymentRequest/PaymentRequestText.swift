//
//  PaymentRequestText.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// A request's title and description as the viewer reads them.
public struct PaymentRequestText: Hashable, Sendable {
    public let title: String
    public let description: String

    /// What a request with no title is called where a title is drawn, the word the deck card and the
    /// details screen already head a request with.
    public static let untitled = "Request"

    /// The title to draw: `title`, or ``untitled`` when the request has none.
    public var displayTitle: String { title.isEmpty ? Self.untitled : title }

    /// `request`'s text, opened with `seal` when it is encrypted. A split with no text has neither a
    /// title nor a description, which the contract allows. `nil` when the request isn't a split, or its
    /// encrypted text has an unknown scheme or fails to open: the card then renders as unsupported.
    public init?(request: GroupPaymentRequest, seal: ChatSeal?) {
        guard let split = request.split else { return nil }
        switch split.text {
        case .plaintext(let title, let description):
            self.title = title
            self.description = description
        case .encrypted(let scheme, let nonce, let ciphertext):
            guard
                let seal,
                let opened = try? seal.openRequestText(scheme: scheme, nonce: nonce, ciphertext: ciphertext, creator: request.creator)
            else { return nil }
            self.title = opened.title
            self.description = opened.description
        case nil:
            self.title = ""
            self.description = ""
        }
    }
}
