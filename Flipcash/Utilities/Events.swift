//
//  Events.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import FlipcashCore

// MARK: - Domain Event Enums -

extension Analytics {
    enum GeneralEvent: String, AnalyticsEvent {
        case autoLoginComplete     = "Auto-login complete"
        case completeOnboarding    = "Complete Onboarding"
        case cancelPendingPurchase = "Cancel Pending Purchase"
    }

    enum AccountEvent: String, AnalyticsEvent {
        case createAccount = "Create Account"
    }

    enum ButtonEvent: String, AnalyticsEvent {
        case createAccount  = "Button: Create Account"
        case saveAccessKey  = "Button: Save Access Key"
        case wroteAccessKey = "Button: Wrote Access Key"
        case allowCamera    = "Button: Allow Camera"
        case allowPush        = "Button: Allow Push"
        case skipPush         = "Button: Skip Push"
        case buyWithReserves  = "Button: Buy With Reserves"
        case buyWithPhantom   = "Button: Buy With Phantom"
        case buyWithCoinbase  = "Button: Buy With Coinbase"
        case give             = "Button: Give"
        case sell             = "Button: Sell"
        case shareTokenInfo   = "Button: Share Token Info"
    }

    enum TransferEvent: String, AnalyticsEvent {
        case withdrawal      = "Withdrawal"
        case sendCashLink    = "Send Cash Link"
        case receiveCashLink = "Receive Cash Link"
        case grabBill        = "Grab Bill"
        case giveBill        = "Give Bill"
        case grabBillStart   = "Grab Bill Start"
        case giveBillStart   = "Give Bill Start"
    }

    enum OnrampEvent: String, AnalyticsEvent {
        case showVerificationInfo = "Onramp: Show Verification Info"
        case showEnterPhone       = "Onramp: Show Enter Phone"
        case showConfirmPhone     = "Onramp: Show Confirm Phone"
        case showEnterEmail       = "Onramp: Show Enter Email"
        case showConfirmEmail     = "Onramp: Show Confirm Email"
        case invokePayment        = "Onramp: Invoke Payment Custom"
        case completed            = "Onramp: Completed"
    }

    enum WalletEvent: String, AnalyticsEvent {
        case connect               = "Wallet: Connect"
        case requestAmount         = "Wallet: Request Amount"
        case transactionsSubmitted = "Wallet: Transactions Submitted"
        case transactionsFailed    = "Wallet: Transactions Failed"
        case cancel                = "Wallet: Cancel"
    }

    enum TokenInfoEvent: String, AnalyticsEvent {
        case openedFromDeeplink = "Token Info: Opened From Deeplink"
        case openedFromWallet   = "Token Info: Opened From Wallet"
        case openedFromGive     = "Token Info: Opened From Give"
    }

    enum TokenTransactionEvent: String, AnalyticsEvent {
        case purchaseWithReserves = "Token Purchase With Reserves"
        case purchaseWithPhantom  = "Token Purchase With Phantom"
        case purchaseWithCoinbase = "Token Purchase With Coinbase"
        case sell                 = "Token Sell"
    }

    enum CurrencyLaunchEvent: String, AnalyticsEvent {
        case launchWithReserves = "Currency Launch With Reserves"
        case launchWithPhantom  = "Currency Launch With Phantom"
        case launchWithCoinbase = "Currency Launch With Coinbase"
    }

    enum DeeplinkEvent: String, AnalyticsEvent {
        case open   = "Deeplink: Open"
        case parse  = "Deeplink: Parse"
        case routed = "Deeplink: Routed"
    }
}

// MARK: - General -

extension Analytics {
    static func buttonTapped(name: ButtonEvent) {
        track(event: name)
    }
}

// MARK: - Account -

extension Analytics {
    static func createAccount(owner: PublicKey) {
        track(
            event: AccountEvent.createAccount,
            properties: [
                .ownerPublicKey: owner.base58,
            ]
        )
    }
}

// MARK: - Cash Transfer -

extension Analytics {
    static func transferStart(event: TransferEvent) {
        track(event: event)
    }

    static func withdrawal(exchangedFiat: ExchangedFiat?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]

        if let exchangedFiat {
            properties[.usdc]     = exchangedFiat.underlying.doubleValue
            properties[.mint]     = exchangedFiat.mint.base58
            properties[.quarks]   = exchangedFiat.underlying.quarks.analyticsValue
            properties[.fiat]     = exchangedFiat.converted.doubleValue
            properties[.fx]       = exchangedFiat.rate.fx.analyticsValue
            properties[.currency] = exchangedFiat.rate.currency.rawValue
        }

        track(
            event: TransferEvent.withdrawal,
            properties: properties,
            error: error
        )
    }

    static func transfer(event: TransferEvent, exchangedFiat: ExchangedFiat?, grabTime: Double?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]

        if let exchangedFiat {
            properties[.usdc]     = exchangedFiat.underlying.doubleValue
            properties[.mint]     = exchangedFiat.mint.base58
            properties[.quarks]   = exchangedFiat.underlying.quarks.analyticsValue
            properties[.fiat]     = exchangedFiat.converted.doubleValue
            properties[.fx]       = exchangedFiat.rate.fx.analyticsValue
            properties[.currency] = exchangedFiat.rate.currency.rawValue
        }

        if let grabTime {
            properties[.grabTime] = grabTime
        }

        track(
            event: event,
            properties: properties,
            error: error
        )
    }

    static func transfer(event: TransferEvent, fiat: Quarks?, successful: Bool, error: Error?) {
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

// MARK: - Onramp -

extension Analytics {
    static func onrampInvokePayment(amount: Quarks) {
        var properties: [Property: AnalyticsValue] = [:]

        properties[.fiat]     = amount.doubleValue
        properties[.currency] = amount.currencyCode.rawValue

        track(event: OnrampEvent.invokePayment, properties: properties)
    }

    static func onrampCompleted(amount: Quarks?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]

        if let amount {
            properties[.fiat]     = amount.doubleValue
            properties[.currency] = amount.currencyCode.rawValue
        }

        track(
            event: OnrampEvent.completed,
            properties: properties,
            error: error
        )
    }
}

// MARK: - Wallet -

extension Analytics {
    static func walletRequestAmount(amount: Quarks) {
        var properties: [Property: AnalyticsValue] = [:]

        properties[.fiat]     = amount.doubleValue
        properties[.currency] = amount.currencyCode.rawValue

        track(event: WalletEvent.requestAmount, properties: properties)
    }
}

// MARK: - Token Info -

extension Analytics {
    static func tokenInfoOpened(from event: TokenInfoEvent, mint: PublicKey) {
        track(event: event, properties: [.mint: mint.base58])
    }
}

// MARK: - Token Transactions -

extension Analytics {
    static func tokenPurchase(method: TokenTransactionEvent, exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        let properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
            .mint: exchangedFiat.mint.base58,
            .fiat: exchangedFiat.converted.doubleValue,
            .currency: exchangedFiat.rate.currency.rawValue,
        ]
        track(event: method, properties: properties, error: error)
    }

    static func tokenSell(exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        let properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
            .mint: exchangedFiat.mint.base58,
            .fiat: exchangedFiat.converted.doubleValue,
            .currency: exchangedFiat.rate.currency.rawValue,
        ]
        track(event: TokenTransactionEvent.sell, properties: properties, error: error)
    }
}

// MARK: - Currency Launch -

extension Analytics {
    static func currencyLaunch(event: CurrencyLaunchEvent, launchedMint: PublicKey, exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        let properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
            .mint: launchedMint.base58,
            .fiat: exchangedFiat.converted.doubleValue,
            .currency: exchangedFiat.rate.currency.rawValue,
        ]
        track(event: event, properties: properties, error: error)
    }
}

// MARK: - Deeplinks -

extension Analytics {
    static func deeplinkOpened(url: URL) {
        track(event: DeeplinkEvent.open, properties: [
            .url: url.sanitizedForAnalytics,
        ])
    }

    static func deeplinkParsed(action: DeepLinkAction?, url: URL) {
        var properties: [Property: AnalyticsValue] = [:]

        if let action {
            properties[.type] = action.kind.analyticsName
        } else {
            properties[.error] = "Failed to parse deeplink => \(url.sanitizedForAnalytics)"
        }

        track(event: DeeplinkEvent.parse, properties: properties)
    }

    static func deeplinkRouted(kind: DeepLinkAction.Kind, error: Error? = nil) {
        track(
            event: DeeplinkEvent.routed,
            properties: [.type: kind.analyticsName],
            error: error
        )
    }
}

// MARK: - Definitions -

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
        case mint              = "Mint"
        case fiat              = "Fiat"
        case currency          = "Currency"
        case fx                = "Exchange Rate"
        case animation         = "Animation"
        case rendezvous        = "Rendezvous"

        case type              = "Type"
        case error             = "Error"
        case url               = "URL"
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
