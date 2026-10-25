//
//  PaymentRequestText.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// A request's title and description as the viewer reads them.
struct PaymentRequestText: Hashable {
    let title: String
    let description: String

    /// `request`'s text, opened with `seal` when it is encrypted. `nil` when the text is missing, its
    /// scheme is unknown, or it fails to open: the card then renders as unsupported.
    init?(request: GroupPaymentRequest, seal: ChatSeal?) {
        switch request.split?.text {
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
            return nil
        }
    }
}
