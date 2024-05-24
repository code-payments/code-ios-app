//
//  Events.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import CodeServices

// MARK: - Open -

extension Analytics {
    
    /// Limit the number of events we send to Mixpanel, this is a no-op for the short term.
    static func open(screen: Screen) {
//        track(.open, properties: [
//            .screen: screen.rawValue,
//        ])
    }
    
    static func unintentialLogout() {
        track(.unintentionalLogout)
    }
    
    static func userMigrationFailed() {
        track(.userMigrationFailed)
    }
}

// MARK: - Account -

extension Analytics {
    static func logout() {
        track(.logout)
    }
    
    static func login(ownerPublicKey: PublicKey, autoCompleteCount: Int, inputChangeCount: Int) {
        track(.login, properties: [
            .ownerPublicKey: ownerPublicKey.base58,
            .autoCompleteCount: autoCompleteCount,
            .inputChangeCount: inputChangeCount,
        ])
    }
    
    static func createAccount(isSuccessful: Bool, ownerPublicKey: PublicKey?, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .result: isSuccessful,
        ]
        
        if let ownerPublicKey = ownerPublicKey {
            properties[.ownerPublicKey] = ownerPublicKey.base58
        }
        
        track(.createAccount, properties: properties, error: error)
    }
}

// MARK: - Bill -

extension Analytics {
    static func billTimeoutReached(kin: Kin, currency: CurrencyCode, animation: PresentationState.Style) {
        track(.bill, properties: [
            .state: String.timedOut,
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
            .animation: animation.description,
        ])
    }
    
    static func billShown(kin: Kin, currency: CurrencyCode, animation: PresentationState.Style) {
        track(.bill, properties: [
            .state: String.shown,
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
            .animation: animation.description,
        ])
    }
    
    static func billHidden(kin: Kin, currency: CurrencyCode, animation: PresentationState.Style) {
        track(.bill, properties: [
            .state: String.hidden,
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
            .animation: animation.description,
        ])
    }
}

// MARK: - Request -

extension Analytics {
    static func requestShown(amount: KinAmount) {
        track(.request, properties: [
            .state: String.shown,
            .amount: amount.kin.analyticsValue,
            .fiat: amount.fiat.analyticsValue,
            .currency: amount.rate.currency.rawValue,
        ])
    }
    
    static func requestHidden(amount: KinAmount) {
        track(.request, properties: [
            .state: String.hidden,
            .amount: amount.kin.analyticsValue,
            .fiat: amount.fiat.analyticsValue,
            .currency: amount.rate.currency.rawValue,
        ])
    }
}

// MARK: - Login -

extension Analytics {
    static func loginCardShown(domain: Domain) {
        track(.loginCard, properties: [
            .state: String.shown,
            .domain: domain.relationshipHost,
        ])
    }
}

extension PresentationState.Style {
    var description: String {
        switch self {
        case .pop:   return String.pop
        case .slide: return String.slide
        }
    }
}

// MARK: - Tips -

extension Analytics {
    static func tipCardShown(username: String) {
        track(.tipCard, properties: [
            .state: String.shown,
            .xUsername: username,
        ])
    }
}

// MARK: - Swap -

extension Analytics {
    static func backgroundSwapInitiated() {
        track(.backgroundSwap)
    }
}

// MARK: - Cash Transfer -

extension Analytics {
    static func transfer(amount: KinAmount, currency: CurrencyCode, successful: Bool, error: Error?) {
        track(.transfer, properties: [
            .state: successful ? String.success : String.failure,
            .amount: amount.kin.analyticsValue,
            .fiat: amount.fiat.analyticsValue,
            .fx: amount.rate.fx.analyticsValue,
            .currency: currency.rawValue,
        ], error: error)
    }
    
    static func transferForRequest(amount: KinAmount, successful: Bool, error: Error?) {
        track(.requestPayment, properties: [
            .state: successful ? String.success : String.failure,
            .amount: amount.kin.analyticsValue,
            .fiat: amount.fiat.analyticsValue,
            .fx: amount.rate.fx.analyticsValue,
            .currency: amount.rate.currency.rawValue,
        ], error: error)
    }
    
    static func transferForTip(amount: KinAmount, successful: Bool, error: Error?) {
        track(.tip, properties: [
            .state: successful ? String.success : String.failure,
            .amount: amount.kin.analyticsValue,
            .fiat: amount.fiat.analyticsValue,
            .fx: amount.rate.fx.analyticsValue,
            .currency: amount.rate.currency.rawValue,
        ], error: error)
    }
    
    static func remoteSendOutgoing(kin: Kin, currency: CurrencyCode) {
        track(.remoteSendOutgoing, properties: [
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
        ])
    }
    
    static func remoteSendIncoming(kin: Kin, currency: CurrencyCode, isVoiding: Bool) {
        track(.remoteSendIncoming, properties: [
            .voidingSend: isVoiding ? String.yes : String.no,
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
        ])
    }
    
    static func grab(kin: Kin, currency: CurrencyCode, millisecondsToGrab: Stopwatch.Milliseconds) {
        track(.grab, properties: [
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
            .grabTime: millisecondsToGrab,
        ])
    }
    
    static func cashLinkGrab(kin: Kin, currency: CurrencyCode, millisecondsToGrab: Stopwatch.Milliseconds) {
        track(.cashLinkGrab, properties: [
            .amount: kin.analyticsValue,
            .currency: currency.rawValue,
            .grabTime: millisecondsToGrab,
        ])
    }
    
    static func upgradePrivacy(successful: Bool, intentID: PublicKey, actionCount: Int, error: Error?) {
        track(.upgradePrivacy, properties: [
            .state: successful ? String.success : String.failure,
            .intentID: intentID.base58,
            .actionCount: actionCount
        ], error: error)
    }
    
    static func claimGetFreeKin(kin: Kin) {
        track(.claimGetFreeKin, properties: [
            .amount: kin.analyticsValue,
        ])
    }
    
    static func errorRequest(amount: KinAmount, rendezvous: PublicKey, error: Error) {
        track(.errorRequest, properties: [
            .amount: amount.kin.analyticsValue,
            .fiat: amount.fiat.analyticsValue,
            .fx: amount.rate.fx.analyticsValue,
            .rendezvous: rendezvous.base58,
        ], error: error)
    }
    
    static func recomputed(fxIn: Decimal, fxOut: Decimal) {
        let delta = ((fxOut / fxIn) - 1) * 100
        track(.recompute, properties: [
            .percentDelta: delta.analyticsValue,
        ])
    }
}

// MARK: - Migration -

extension Analytics {
    static func migration(amount: Kin) {
        track(.privacyMigration, properties: [
            .amount: amount.analyticsValue,
        ])
    }
}

// MARK: - Definitions -

extension Analytics {
    enum Name: String {
        
        // Open
        case open = "Open"
        
        // Account
        case logout = "Logout"
        case login = "Login"
        case createAccount = "Create Account"
        case unintentionalLogout = "Unintentional Logout"
        case userMigrationFailed = "User Migration Failed"
        
        // Bill
        case bill = "Bill"
        case request = "Request Card"
        case loginCard = "Login Card"
        case tipCard = "Tip Card"
        
        // Transfer
        case transfer = "Transfer"
        case requestPayment = "Request Payment"
        case tip = "Tip"
        case remoteSendOutgoing = "Remote Send Outgoing"
        case remoteSendIncoming = "Remote Send Incoming"
        case grab = "Grab"
        case cashLinkGrab = "Cash Link Grab"
        case upgradePrivacy = "Upgrade Privacy"
        case claimGetFreeKin = "Claim Get Free Kin"
        
        case privacyMigration = "Privacy Migration"
        
        case backgroundSwap = "Background Swap Initiated"
        
        // Errors
        case errorRequest = "Error Request"
        
        case recompute = "Recompute"
    }
}

extension Analytics {
    enum Property: String {
        
        // Open
        case screen = "Screen"
        
        // Account
        case ownerPublicKey = "Owner Public Key"
        case autoCompleteCount = "Auto-complete count"
        case inputChangeCount = "Input change count"
        case result = "Result"
        case grabTime = "Grab Time"
        
        // Bill
        case state = "State"
        case amount = "Amount"
        case fiat = "Fiat"
        case currency = "Currency"
        case fx = "Exchange Rate"
        case animation = "Animation"
        case rendezvous = "Rendezvous"
        case domain = "Domain"
        case xUsername = "X Username"
        
        // Validation
        case type = "Type"
        case error = "Error"
        
        // Privacy Upgrade
        case intentID = "Intent ID"
        case actionCount = "Action Count"
        
        // Remote Send
        case voidingSend = "Voiding Send"
        
        case percentDelta = "Percent Delta"
    }
}

extension Analytics {
    enum Screen: String {
        case permission = "Permission Screen"
        case verifyPhone = "Verify Phone Screen"
        case inviteCode = "Invite Code Screen"
        case confirmPhone = "Confirm Phone Screen"
        case regionSelection = "Region Selection Screen"
        case login = "Login Screen"
        case migration = "Migration Screen"
        case restricted = "Restricted Screen"
        case accountSelection = "Account Selection Screen"
        case contacts = "Contacts Screen"
        case buckets = "Buckets Screen"
        case currencySelection = "Currency Selection Screen"
        case giveKin = "Give Kin Screen"
        case balance = "Balance Screen"
        case faq = "FAQ Screen"
        case settings = "Settings Screen"
        case deposit = "Deposit Screen"
        case backup = "Backup Screen"
        case linkPhone = "Link Phone Screen"
        case deleteAccount = "Delete Account Screen"
        case confirmDelete = "Confirm Delete Screen"
        case withdrawAmount = "Withdraw Amount Screen"
        case withdrawAddress = "Withdraw Address Screen"
        case withdrawSummary = "Withdraw Summary Screen"
        case debug = "Debug Screen"
        case forceUpgrade = "Force Upgrade"
        case getKin = "Get Kin Screen"
        case getFriendStarted = "Get Friend Started Screen"
        case buyVideo = "Buy Video Screen"
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

extension Kin {
    var analyticsValue: Int {
        Int(truncatedKinValue)
    }
}

extension Decimal {
    var analyticsValue: Double {
        doubleValue
    }
}
