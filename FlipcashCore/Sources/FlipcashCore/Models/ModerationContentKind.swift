//
//  ModerationContentKind.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// What a piece of text is moderated as. The server moderates it under that
/// kind's checks, refuses text over the kind's maximum length (32 bytes for a
/// currency name, 8 for a symbol), and binds the kind into the attestation,
/// which is then valid only where the text is used as that kind.
public enum ModerationTextKind: Sendable {
    case currencyName
    case currencySymbol
    case currencyDescription
}

/// What an image is moderated as, bound into the attestation the same way as
/// ``ModerationTextKind``.
public enum ModerationImageKind: Sendable {
    case currencyIcon
}

extension ModerationTextKind {
    var proto: Flipcash_Moderation_V1_ContentKind {
        switch self {
        case .currencyName:        .currencyName
        case .currencySymbol:      .currencySymbol
        case .currencyDescription: .currencyDescription
        }
    }
}

extension ModerationImageKind {
    var proto: Flipcash_Moderation_V1_ContentKind {
        switch self {
        case .currencyIcon: .currencyIcon
        }
    }
}
