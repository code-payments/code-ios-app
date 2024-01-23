//
//  BillState.swift
//  Code
//
//  Created by Dima Bart on 2021-02-25.
//

import Foundation
import CodeServices
import CodeUI

struct BillState: Equatable {
    
    var bill: Bill?
    var shouldShowToast: Bool
    var toast: Toast?
    var valuation: Valuation?
    var paymentConfirmation: PaymentConfirmation?
    var loginConfirmation: LoginConfirmation?
    var hideBillButtons: Bool
    
    fileprivate init(bill: Bill?, shouldShowDeposit: Bool = false, toast: Toast? = nil, valuation: Valuation? = nil, paymentConfirmation: PaymentConfirmation? = nil, loginConfirmation: LoginConfirmation? = nil, hideBillButtons: Bool = false) {
        self.bill                = bill
        self.shouldShowToast     = shouldShowDeposit
        self.toast               = toast
        self.valuation           = valuation
        self.paymentConfirmation = paymentConfirmation
        self.loginConfirmation   = loginConfirmation
        self.hideBillButtons     = hideBillButtons
    }
}

// MARK: - Modifiers -

extension BillState {
    static func `default`() -> BillState {
        BillState(bill: nil)
    }
    
    func bill(_ bill: Bill?) -> BillState {
        var state = self
        state.bill = bill
        return state
    }
    
    func shouldShowToast(_ value: Bool) -> BillState {
        var state = self
        state.shouldShowToast = value
        return state
    }
    
    func showToast(_ toast: Toast?) -> BillState {
        var state = self
        state.toast = toast
        return state
    }
    
    func showValuation(_ valuation: Valuation?) -> BillState {
        var state = self
        state.valuation = valuation
        return state
    }
    
    func showPaymentConfirmation(_ paymentConfirmation: PaymentConfirmation?) -> BillState {
        var state = self
        state.paymentConfirmation = paymentConfirmation
        return state
    }
    
    func showLoginConfirmation(_ loginConfirmation: LoginConfirmation?) -> BillState {
        var state = self
        state.loginConfirmation = loginConfirmation
        return state
    }
    
    func hideBillButtons(_ value: Bool) -> BillState {
        var state = self
        state.hideBillButtons = value
        return state
    }
}

// MARK: - Toast -

extension BillState {
    struct Toast: Equatable {
        var amount: KinAmount
        var isDeposit: Bool
    }
}

// MARK: - Valuation -

extension BillState {
    struct Valuation: Equatable {
        var title: String
        var amount: KinAmount
    }
}

// MARK: - Payment Confirmation -

extension BillState {
    struct PaymentConfirmation: Equatable {
        var payload: Code.Payload
        var requestedAmount: KinAmount
        var localAmount: KinAmount
    }
}

extension BillState {
    struct LoginConfirmation: Equatable {
        var payload: Code.Payload
        var domain: Domain
    }
}

// MARK: - Bill (Metadata) -

extension BillState {
    enum Bill: Equatable {
        
        case cash(Metadata)
        case request(Metadata)
        case login(Metadata)
        
        var canSwipeToDismiss: Bool {
            switch self {
            case .cash:    return true
            case .request: return false
            case .login:   return false
            }
        }
        
        var metadata: Metadata {
            switch self {
            case .cash(let m):    return m
            case .request(let m): return m
            case .login(let m):   return m
            }
        }
    }
}

extension BillState {
    struct Metadata: Equatable {
        var kinAmount: KinAmount
        var data: Data
        var request: DeepLinkRequest?
    }
}
