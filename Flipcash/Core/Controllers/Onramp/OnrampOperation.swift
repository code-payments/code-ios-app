//
//  OnrampOperation.swift
//  Flipcash
//

import Foundation
import FlipcashCore

enum OnrampOperation {
    case buy(
        mint: PublicKey,
        displayName: String,
        onCompleted: @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    )
    case launch(
        displayName: String,
        onCompleted: @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    )

    var displayName: String {
        switch self {
        case .buy(_, let displayName, _): displayName
        case .launch(let displayName, _): displayName
        }
    }

    var logKind: String {
        switch self {
        case .buy:    "buy_existing"
        case .launch: "launch_new"
        }
    }
}
