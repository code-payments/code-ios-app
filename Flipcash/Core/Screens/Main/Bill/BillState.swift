//
//  BillState.swift
//  Code
//
//  Created by Dima Bart on 2021-02-25.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct BillState {

    var bill: Bill?

    /// Whether the bill has given the screen to what comes next and is only
    /// finishing its exit. It still draws — the overlay sits above the whole
    /// app — but the screen underneath is now the one being used, so a
    /// handing-off bill stops dimming it and stops taking its touches.
    ///
    /// Cleared with the bill, by ``BillState/default()``.
    var isHandingOff: Bool = false

    var primaryAction: PrimaryAction?
    var secondaryAction: SecondaryAction?

    init(bill: Bill?, primaryAction: PrimaryAction? = nil, secondaryAction: SecondaryAction? = nil) {
        self.bill            = bill
        self.primaryAction   = primaryAction
        self.secondaryAction = secondaryAction
    }
}

// MARK: - Modifiers -

extension BillState {
    static func `default`() -> BillState {
        BillState(bill: nil)
    }
}

extension BillState {
    struct PrimaryAction {
        var asset: Asset
        var title: String
        var action: ThrowingAction
    }
}

extension BillState {
    struct SecondaryAction {
        var asset: Asset
        var title: String?
        var action: VoidAction
    }
}

// MARK: - Bill (Metadata) -

extension BillState {
    enum Bill: Equatable {

        case cash(CashCode.Payload, mint: PublicKey, billColors: [String] = [])
        /// A scanned (or deeplinked) recipient's tipcard, shown over the
        /// camera as the confirmation of whose code was read, then held over
        /// the chat it hands off to while that chat arrives.
        case tipcard(codeData: Data, name: String, username: String?, avatar: UIImage?)

        var canSwipeToDismiss: Bool {
            switch self {
            case .cash, .tipcard: return true
            }
        }
    }
}
