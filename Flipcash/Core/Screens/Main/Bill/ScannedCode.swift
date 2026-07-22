//
//  ScannedCode.swift
//  Flipcash
//

import Foundation

/// A decoded scan from the camera, dispatched on the frame's leading kind
/// byte: cash bills carry a rendezvous + amount, tipcodes carry a user id.
nonisolated enum ScannedCode {

    case cash(CashCode.Payload)
    case tip(TipCode.Payload)

    init?(data: Data) {
        guard let kindByte = data.first else {
            return nil
        }

        switch kindByte {
        case CashCode.Payload.Kind.cash.rawValue,
             CashCode.Payload.Kind.cashMulticurrency.rawValue:
            guard let payload = try? CashCode.Payload(data: data) else {
                return nil
            }
            self = .cash(payload)
        case TipCode.Payload.kind:
            guard let payload = try? TipCode.Payload(data: data) else {
                return nil
            }
            self = .tip(payload)
        default:
            return nil
        }
    }
}
