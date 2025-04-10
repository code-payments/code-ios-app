//
//  IntentMetadata+Types.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation

public struct PaymentMetadata: Equatable, Sendable {
    
    public let exchangedFiat: ExchangedFiat
    
    init(exchangedFiat: ExchangedFiat) {
        self.exchangedFiat = exchangedFiat
    }
}
