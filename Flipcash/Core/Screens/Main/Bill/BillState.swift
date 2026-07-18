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

        var canSwipeToDismiss: Bool {
            switch self {
            case .cash: return true
            }
        }

        var mint: PublicKey {
            switch self {
            case .cash(_, let mint, _):
                return mint
            }
        }
    }
}
