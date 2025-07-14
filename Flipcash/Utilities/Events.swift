//
//  Events.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import FlipcashCore


// MARK: - Account -

extension Analytics {
//    static func logout() {
//        track(.logout)
//    }
    
//    static func login(ownerPublicKey: PublicKey, autoCompleteCount: Int, inputChangeCount: Int) {
//        track(.login, properties: [
//            .ownerPublicKey: ownerPublicKey.base58,
//            .autoCompleteCount: autoCompleteCount,
//            .inputChangeCount: inputChangeCount,
//        ])
//    }
    
//    static func loginByRetry(count: Int) {
//        track(.loginByRetry, properties: [
//            .retryCount: count,
//        ])
//    }
    
//    static func createAccount(isSuccessful: Bool, ownerPublicKey: PublicKey?, error: Error?) {
//        var properties: [Property: AnalyticsValue] = [
//            .result: isSuccessful,
//        ]
//        
//        if let ownerPublicKey = ownerPublicKey {
//            properties[.ownerPublicKey] = ownerPublicKey.base58
//        }
//        
//        track(.createAccount, properties: properties, error: error)
//    }
    
    static func cancelPendingPurchase() {
        track(event: .cancelPendingPurchase)
    }
    
    static func createAccount(owner: PublicKey) {
        track(
            event: .createAccount,
            properties: [
                .ownerPublicKey: owner.base58,
            ]
        )
    }
}

// MARK: - Cash Transfer -

extension Analytics {
    
    static func withdrawal(exchangedFiat: ExchangedFiat?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]
        
        if let exchangedFiat {
            properties[.usdc]     = exchangedFiat.usdc.doubleValue
            properties[.quarks]   = exchangedFiat.usdc.quarks.analyticsValue
            properties[.fiat]     = exchangedFiat.converted.doubleValue
            properties[.fx]       = exchangedFiat.rate.fx.analyticsValue
            properties[.currency] = exchangedFiat.rate.currency.rawValue
        }
        
        track(
            event: .withdrawal,
            properties: properties,
            error: error
        )
    }
    
    static func transfer(event: Name, exchangedFiat: ExchangedFiat?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]
        
        if let exchangedFiat {
            properties[.usdc]     = exchangedFiat.usdc.doubleValue
            properties[.quarks]   = exchangedFiat.usdc.quarks.analyticsValue
            properties[.fiat]     = exchangedFiat.converted.doubleValue
            properties[.fx]       = exchangedFiat.rate.fx.analyticsValue
            properties[.currency] = exchangedFiat.rate.currency.rawValue
        }
        
        track(
            event: event,
            properties: properties,
            error: error
        )
    }
    
    static func transfer(event: Name, fiat: Fiat?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]
        
        if let fiat {
            properties[.usdc]   = fiat.doubleValue
            properties[.quarks] = fiat.quarks.analyticsValue
        }
        
        track(
            event: event,
            properties: properties,
            error: error
        )
    }
}

// MARK: - Definitions -

extension Analytics {
    enum Name: String {
        case createAccount   = "Create Account"
        case withdrawal      = "Withdrawal"
        case sendCashLink    = "Send Cash Link"
        case receiveCashLink = "Receive Cash Link"
        case grabBill        = "Grab Bill"
        case giveBill        = "Give Bill"
        
        case cancelPendingPurchase = "Cancel Pending Purchase"
    }
}

extension Analytics {
    enum Property: String {
        
        case ownerPublicKey    = "Owner Public Key"
        case autoCompleteCount = "Auto-complete count"
        case inputChangeCount  = "Input change count"
        case result            = "Result"
        case grabTime          = "Grab Time"
        case time              = "Time"
        
        case state             = "State"
        case quarks            = "Quarks"
        case usdc              = "USDC"
        case fiat              = "Fiat"
        case currency          = "Currency"
        case fx                = "Exchange Rate"
        case animation         = "Animation"
        case rendezvous        = "Rendezvous"
        
        case type              = "Type"
        case error             = "Error"
    }
}

private extension String {
    static let success  = "Success"
    static let failure  = "Failure"
    static let shown    = "Shown"
    static let hidden   = "Hidden"
    static let timedOut = "Timed Out"
    static let pop      = "Pop"
    static let slide    = "Slide"
    static let yes      = "Yes"
    static let no       = "No"
}

extension Decimal {
    var analyticsValue: Double {
        doubleValue
    }
}

extension UInt64 {
    var analyticsValue: UInt {
        UInt(self)
    }
}
