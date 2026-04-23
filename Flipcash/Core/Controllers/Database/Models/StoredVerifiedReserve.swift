//
//  StoredVerifiedReserve.swift
//  Code
//

import Foundation

struct StoredVerifiedReserve: Equatable {
    let mint: String          // base58 PublicKey
    let reserveProto: Data    // serialized Ocp_Currency_V1_VerifiedLaunchpadCurrencyReserveState
    let receivedAt: Date
}
