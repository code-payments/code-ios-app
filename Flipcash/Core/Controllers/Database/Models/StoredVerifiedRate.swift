//
//  StoredVerifiedRate.swift
//  Code
//

import Foundation

struct StoredVerifiedRate: Equatable, Sendable {
    let currency: String   // matches CurrencyCode raw value
    let rateProto: Data    // serialized Ocp_Currency_V1_VerifiedCoreMintFiatExchangeRate
    let receivedAt: Date   // when we received it from the stream (recorded for debugging)
}
