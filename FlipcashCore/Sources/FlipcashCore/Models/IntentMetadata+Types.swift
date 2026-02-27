//
//  IntentMetadata+Types.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation

public struct PaymentMetadata: Equatable, Sendable {

    public let exchangedFiat: ExchangedFiat
    public let verifiedState: VerifiedState?

    public init(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState? = nil) {
        self.exchangedFiat = exchangedFiat
        self.verifiedState = verifiedState
    }
}
