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
        /// camera while the Send a Tip sheet is up.
        case tipcard(codeData: Data, name: String, avatar: UIImage?)

        var canSwipeToDismiss: Bool {
            switch self {
            case .cash, .tipcard: return true
            }
        }
    }
}
