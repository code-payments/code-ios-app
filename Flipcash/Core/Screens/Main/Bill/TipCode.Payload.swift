//
//  TipCode.Payload.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// A scannable code identifying a user so others can tip them.
///
/// Deliberately not a `CashCode.Payload` kind: that type derives a rendezvous
/// keypair from a fiat amount, which a profile code does not have. Both share
/// the 20-byte frame, so one scanner can dispatch on the leading kind byte.
nonisolated enum TipCode {

    struct Payload: Equatable {
        let userID: UserID
    }
}
