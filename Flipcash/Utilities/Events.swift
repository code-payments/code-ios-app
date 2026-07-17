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
        case buyWithCurrency  = "Button: Buy With Currency"
        case give             = "Button: Give"
        case sell             = "Button: Sell"
        case shareTokenInfo   = "Button: Share Token Info"
    }

    enum TransferEvent: String, AnalyticsEvent {
        case withdrawal      = "Withdrawal"
        case sentCash        = "Sent Cash"
        case sendCashLink    = "Send Cash Link"
        case receiveCashLink = "Receive Cash Link"
        case grabBill        = "Grab Bill"
        case giveBill        = "Give Bill"
        case grabBillStart   = "Grab Bill Start"
        case giveBillStart   = "Give Bill Start"
    }

    enum OnrampEvent: String, AnalyticsEvent {
        case showEnterPhone       = "Onramp: Show Enter Phone"
        case showConfirmPhone     = "Onramp: Show Confirm Phone"
        case showEnterEmail       = "Onramp: Show Enter Email"
        case showConfirmEmail     = "Onramp: Show Confirm Email"
        case invokePayment        = "Onramp: Invoke Payment Custom"
        case completed            = "Onramp: Completed"
    }

    enum SendEvent: String, AnalyticsEvent {
        case showEnterPhone   = "Send: Show Enter Phone"
        case showConfirmPhone = "Send: Show Confirm Phone"
    }

    enum ConversationEvent: String, AnalyticsEvent {
        case sentMessage = "Sent Message"
    }

    enum PhoneEvent: String, AnalyticsEvent {
        case entered  = "Entered Phone Number"
        case verified = "Verified Phone Number"
        case linked   = "Linked Phone Number"
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
        case openedFromSend     = "Token Info: Opened From Send"
    }

    enum TokenTransactionEvent: String, AnalyticsEvent {
        case purchaseWithReserves = "Token Purchase With Reserves"
        case purchaseWithCurrency = "Token Purchase With Currency"
        case sell                 = "Token Sell"
        case withdraw             = "Token Withdrawal"
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

    /// The Add Money funnel, modeled after the transfer pattern — a single
    /// terminal event with State/Error properties. Names are shared verbatim
    /// with Android.
    enum AddMoneyEvent: String, AnalyticsEvent {
        case opened          = "Add Money: Opened"
        case methodSelected  = "Add Money: Method Selected"
        case amountConfirmed = "Add Money: Amount Confirmed"
        case paymentInvoked  = "Add Money: Payment Invoked"
        case addressCopied   = "Add Money: Address Copied"
        case terminal        = "Add Money"
    }

    /// The `Source` property of `AddMoneyEvent.opened` — where the user
    /// entered the flow. Values are shared verbatim with Android.
    enum AddMoneySource: String {
        case menu          = "Menu"
        case giveShortfall = "Give Shortfall"
        case buyShortfall  = "Buy Shortfall"
        case chat          = "Chat"
        case scanner       = "Scanner"
        case balance       = "Balance"
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

// MARK: - Shared property builders -

private extension Analytics {
    /// The standard money-amount property block — mint, quarks, native fiat,
    /// exchange rate, and currency. Shared by the transfer and Add Money events.
    static func amountProperties(_ exchangedFiat: ExchangedFiat) -> [Property: AnalyticsValue] {
        [
            .mint:     exchangedFiat.mint.base58,
            .quarks:   exchangedFiat.onChainAmount.quarks.analyticsValue,
            .fiat:     exchangedFiat.nativeAmount.doubleValue,
            .fx:       exchangedFiat.currencyRate.fx.analyticsValue,
            .currency: exchangedFiat.currencyRate.currency.rawValue,
        ]
    }
}

// MARK: - Cash Transfer -

extension Analytics {
    static func transferStart(event: TransferEvent) {
        track(event: event)
    }

    static func withdrawal(exchangedFiat: ExchangedFiat?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = exchangedFiat.map(amountProperties) ?? [:]
        properties[.state] = successful ? String.success : String.failure

        track(
            event: TransferEvent.withdrawal,
            properties: properties,
            error: error
        )
    }

    static func transfer(event: TransferEvent, exchangedFiat: ExchangedFiat?, grabTime: Double?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = exchangedFiat.map(amountProperties) ?? [:]
        properties[.state] = successful ? String.success : String.failure

        if let grabTime {
            properties[.grabTime] = grabTime
        }

        track(
            event: event,
            properties: properties,
            error: error
        )
    }

    static func transfer(event: TransferEvent, fiat: FiatAmount?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]

        if let fiat {
            properties[.fiat]     = fiat.doubleValue
            properties[.currency] = fiat.currency.rawValue
        }

        track(
            event: event,
            properties: properties,
            error: error
        )
    }
}

// MARK: - Add Money -

extension Analytics {
    static func addMoneyOpened(source: AddMoneySource) {
        track(event: AddMoneyEvent.opened, properties: [.source: source.rawValue])
    }

    static func addMoneyMethodSelected(method: DepositMethod) {
        track(event: AddMoneyEvent.methodSelected, properties: [.method: method.analyticsValue])
    }

    static func addMoneyAmountConfirmed(method: DepositMethod, exchangedFiat: ExchangedFiat) {
        var properties = amountProperties(exchangedFiat)
        properties[.method] = method.analyticsValue
        track(event: AddMoneyEvent.amountConfirmed, properties: properties)
    }

    static func addMoneyPaymentInvoked(method: DepositMethod, exchangedFiat: ExchangedFiat) {
        var properties = amountProperties(exchangedFiat)
        properties[.method] = method.analyticsValue
        track(event: AddMoneyEvent.paymentInvoked, properties: properties)
    }

    static func addMoneyAddressCopied(mint: PublicKey) {
        track(event: AddMoneyEvent.addressCopied, properties: [.mint: mint.base58])
    }

    static func addMoney(method: DepositMethod, exchangedFiat: ExchangedFiat?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = exchangedFiat.map(amountProperties) ?? [:]
        properties[.method] = method.analyticsValue
        properties[.state] = successful ? String.success : String.failure
        track(event: AddMoneyEvent.terminal, properties: properties, error: error)
    }
}

extension DepositMethod {
    /// The `Method` property value, shared verbatim with Android.
    var analyticsValue: String {
        switch self {
        case .coinbase:    "Coinbase"
        case .phantom:     "Phantom"
        case .otherWallet: "Other Wallet"
        }
    }
}

// MARK: - Onramp -

extension Analytics {
    static func onrampInvokePayment(amount: FiatAmount) {
        var properties: [Property: AnalyticsValue] = [:]

        properties[.fiat]     = amount.doubleValue
        properties[.currency] = amount.currency.rawValue

        track(event: OnrampEvent.invokePayment, properties: properties)
    }

    static func onrampCompleted(amount: FiatAmount?, successful: Bool, error: Error?) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
        ]

        if let amount {
            properties[.fiat]     = amount.doubleValue
            properties[.currency] = amount.currency.rawValue
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
    static func walletRequestAmount(amount: FiatAmount) {
        var properties: [Property: AnalyticsValue] = [:]

        properties[.fiat]     = amount.doubleValue
        properties[.currency] = amount.currency.rawValue

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
            .fiat: exchangedFiat.nativeAmount.doubleValue,
            .currency: exchangedFiat.currencyRate.currency.rawValue,
        ]
        track(event: method, properties: properties, error: error)
    }

    static func tokenSell(exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        let properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
            .mint: exchangedFiat.mint.base58,
            .fiat: exchangedFiat.nativeAmount.doubleValue,
            .currency: exchangedFiat.currencyRate.currency.rawValue,
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
            .fiat: exchangedFiat.nativeAmount.doubleValue,
            .currency: exchangedFiat.currencyRate.currency.rawValue,
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
        case source            = "Source"
        case method            = "Method"
        case quarks            = "Quarks"
        case mint              = "Mint"
        case fiat              = "Fiat"
        case currency          = "Currency"
        case fx                = "Exchange Rate"
        case animation         = "Animation"
        case rendezvous        = "Rendezvous"

        case type              = "Type"
        case error             = "Error"
        case url               = "URL"

        case title             = "Title"
        case message           = "Message"
        case screen            = "Screen"
        case callSite          = "Call Site"
    }
}

private extension String {
    static let success  = "Success"
    static let failure  = "Failure"
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
