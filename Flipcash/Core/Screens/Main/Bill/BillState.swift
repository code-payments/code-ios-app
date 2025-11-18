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
    var shouldShowToast: Bool
    
    var primaryAction: PrimaryAction?
    var secondaryAction: SecondaryAction?
    
    var hideBillButtons: Bool
    
    init(bill: Bill?, shouldShowDeposit: Bool = false, primaryAction: PrimaryAction? = nil, secondaryAction: SecondaryAction? = nil, hideBillButtons: Bool = false) {
        self.bill            = bill
        self.shouldShowToast = shouldShowDeposit
        self.primaryAction   = primaryAction
        self.secondaryAction = secondaryAction
        self.hideBillButtons = hideBillButtons
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
        var loadingStateDelayMillisenconds: Int? = nil
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

        case cash(CashCode.Payload, mint: PublicKey)

        var canSwipeToDismiss: Bool {
            switch self {
            case .cash: return true
            }
        }

        var mint: PublicKey {
            switch self {
            case .cash(_, let mint):
                return mint
            }
        }
    }
}
