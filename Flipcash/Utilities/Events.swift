//
//  Events.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import FlipcashCore

// MARK: - General -

extension Analytics {
    static func autoLoginComplete() {
        track(event: .autoLoginComplete)
    }
    
    static func buttonTapped(name: Name) {
        track(event: name)
    }
}

// MARK: - Account -

extension Analytics {
    
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

// MARK: - Pools -

extension Analytics {
    static func poolOpenedFromDeeplink(id: PublicKey) {
        track(event: .poolOpened, properties: [
            .id: id.base58
        ])
    }
    
    static func poolCreated(id: PublicKey) {
        track(event: .poolCreated, properties: [
            .id: id.base58
        ])
    }
    
    static func poolPlaceBet(id: PublicKey) {
        track(event: .poolPlaceBet, properties: [
            .id: id.base58
        ])
    }
    
    static func poolDeclareOutcome(id: PublicKey) {
        track(event: .poolDeclareOutcome, properties: [
            .id: id.base58
        ])
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
        
        case buttonCreateAccount  = "Button: Create Account"
        case buttonSaveAccessKey  = "Button: Save Access Key"
        case buttonWroteAccessKey = "Button: Wrote Access Key"
        case buttonAllowCamera    = "Button: Allow Camera"
        case buttonAllowPush      = "Button: Allow Push"
        case buttonSkipPush       = "Button: Skip Push"
        
        case autoLoginComplete    = "Auto-login complete"
        case completeOnboarding   = "Complete Onboarding"
        
        case poolOpened           = "Pool: Opened From Deeplink"
        case poolCreated          = "Pool: Created"
        case poolDeclareOutcome   = "Pool: Declare Outcome"
        case poolPlaceBet         = "Pool: Place Bet"
        
        case cancelPendingPurchase = "Cancel Pending Purchase"
    }
}

extension Analytics {
    enum Property: String {
        
        case id                = "ID"
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
