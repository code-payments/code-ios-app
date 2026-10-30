//
//  PinSlot.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Where a chat's pins show, given what the payment requests hold. Requests win the slot under the
/// bar: while the owed strip is out, the pins shrink to a button in the bar's trailing slot; once the
/// strip has gone into the pill, the pins take the slot under the bar.
enum PinSlot: Hashable {
    /// No visible pins.
    case none
    /// The pin bar under the navigation bar.
    case bar
    /// A pin button in the navigation bar's trailing slot, opening the list.
    case toolbarButton

    /// The slot for a chat that `hasPins`, with its request deck in `deckStyle`, or nil without
    /// requests.
    static func resolve(hasPins: Bool, deckStyle: PaymentRequestDeckStyle?) -> PinSlot {
        guard hasPins else { return .none }
        switch deckStyle {
        case .strip:        return .toolbarButton
        case .pill, nil:    return .bar
        }
    }
}
