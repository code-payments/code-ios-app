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
    var toast: Toast?
    var valuation: Valuation?
    
    var primaryAction: PrimaryAction?
    var secondaryAction: SecondaryAction?
    
    var hideBillButtons: Bool
    
    init(bill: Bill?, shouldShowDeposit: Bool = false, toast: Toast? = nil, valuation: Valuation? = nil, primaryAction: PrimaryAction? = nil, secondaryAction: SecondaryAction? = nil, hideBillButtons: Bool = false) {
        self.bill                = bill
        self.shouldShowToast     = shouldShowDeposit
        self.toast               = toast
        self.valuation           = valuation
        self.primaryAction       = primaryAction
        self.secondaryAction     = secondaryAction
        self.hideBillButtons     = hideBillButtons
    }
}

// MARK: - Modifiers -

extension BillState {
    static func `default`() -> BillState {
        BillState(bill: nil)
    }
}

//extension BillState {
//    static func `default`() -> BillState {
//        BillState(bill: nil)
//    }
//    
//    func bill(_ bill: Bill?) -> BillState {
//        var state = self
//        state.bill = bill
//        return state
//    }
//    
//    func shouldShowToast(_ value: Bool) -> BillState {
//        var state = self
//        state.shouldShowToast = value
//        return state
//    }
//    
//    func showToast(_ toast: Toast?) -> BillState {
//        var state = self
//        state.toast = toast
//        return state
//    }
//    
//    func showValuation(_ valuation: Valuation?) -> BillState {
//        var state = self
//        state.valuation = valuation
//        return state
//    }
//    
//    func primaryAction(_ value: PrimaryAction?) -> BillState {
//        var state = self
//        state.primaryAction = value
//        return state
//    }
//    
//    func secondaryAction(_ value: SecondaryAction?) -> BillState {
//        var state = self
//        state.secondaryAction = value
//        return state
//    }
//    
//    func hideBillButtons(_ value: Bool) -> BillState {
//        var state = self
//        state.hideBillButtons = value
//        return state
//    }
//}

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

// MARK: - Toast -

extension BillState {
    struct Toast: Equatable {
        var amount: Fiat
        var isDeposit: Bool
    }
}

// MARK: - Valuation -

extension BillState {
    struct Valuation: Equatable {
        var title: String
        var amount: Fiat
    }
}

// MARK: - Bill (Metadata) -

extension BillState {
    enum Bill: Equatable {
        
        case cash(Metadata)
        
        var canSwipeToDismiss: Bool {
            switch self {
            case .cash: return true
            }
        }
        
        var metadata: Metadata {
            switch self {
            case .cash(let m): return m
            }
        }
    }
}

extension BillState {
    struct Metadata: Equatable {
        var fiat: Fiat
        var cashCodeData: Data
        
        init(fiat: Fiat, cashCodeData: Data? = nil) {
            self.fiat = fiat
            self.cashCodeData = cashCodeData ?? CashCode.Payload(
                kind: .cash,
                fiat: fiat,
                nonce: .nonce
            ).codeData()
        }
    }
}
