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
        case sentTip         = "Sent Tip"
        case sendCashLink    = "Send Cash Link"
        case receiveCashLink = "Receive Cash Link"
        case grabBill        = "Grab Bill"
        case giveBill        = "Give Bill"
    }

    /// An onramp verification screen, sent as `Onramp: Show <step>`.
    enum OnrampStep {
        case enterPhone
        case confirmPhone
        case enterEmail
        case confirmEmail

        /// The shared contract's step for this screen.
        var shared: SharedCoreKit.OnrampStep {
            switch self {
            case .enterPhone:   .enterPhone
            case .confirmPhone: .confirmPhone
            case .enterEmail:   .enterEmail
            case .confirmEmail: .confirmEmail
            }
        }
    }

    enum SendEvent: String, AnalyticsEvent {
        case showEnterPhone   = "Send: Show Enter Phone"
        case showConfirmPhone = "Send: Show Confirm Phone"
    }

    enum ConversationEvent: String, AnalyticsEvent {
        case tipReceived = "Tip Received"
    }

    /// The display name a user is known by. `Set` is a first name, `Updated` a
    /// replacement — decided by whether a name already existed, not by the screen.
    enum DisplayNameEvent {
        case set
        case updated
    }

    /// The surface a display-name submission came from.
    enum DisplayNameSource {
        case onboarding
        case myAccount
        case tipCardSetup
    }

    enum GalleryScanEvent: String, AnalyticsEvent {
        case codeFound    = "Gallery Scan: Code Found"
        case nothingFound = "Gallery Scan: Nothing Found"
    }

    /// Why a gallery scan came back with nothing. `cancelled` covers both the user tapping
    /// Cancel and the budget running out, which are the same event from the search's side.
    enum GalleryScanMiss: String {
        case exhausted    = "Exhausted"
        case cancelled    = "Cancelled"
        case routeRefused = "Route Refused"
    }

    enum WalletEvent: String, AnalyticsEvent {
        case connect               = "Wallet: Connect"
        case requestAmount         = "Wallet: Request Amount"
        case transactionsSubmitted = "Wallet: Transactions Submitted"
        case transactionsFailed    = "Wallet: Transactions Failed"
        case cancel                = "Wallet: Cancel"
    }

    /// Where Token Info was opened from. Deeplink and Wallet are built by the shared
    /// contract; Give and Send are iOS-only and keep their names here.
    enum TokenInfoEvent {
        case openedFromDeeplink
        case openedFromWallet
        case openedFromGive
        case openedFromSend
    }

    fileprivate enum NativeTokenInfoEvent: String, AnalyticsEvent {
        case openedFromGive = "Token Info: Opened From Give"
        case openedFromSend = "Token Info: Opened From Send"
    }

    enum TokenTransactionEvent: String, AnalyticsEvent {
        case purchaseWithReserves = "Token Purchase With Reserves"
        case purchaseWithCurrency = "Token Purchase With Currency"
        case sell                 = "Token Sell"
        case withdraw             = "Token Withdrawal"
    }

    enum CurrencyLaunchEvent: String, AnalyticsEvent {
        case launchWithReserves = "Currency Launch With Reserves"
        case launchWithCurrency = "Currency Launch With Currency"
    }

    enum DeeplinkEvent: String, AnalyticsEvent {
        case parse  = "Deeplink: Parse"
        case routed = "Deeplink: Routed"
    }

    /// The Add Money funnel, modeled after the transfer pattern — a single
    /// terminal event with State/Error properties. Names are shared verbatim
    /// with Android.
    enum AddMoneyEvent: String, AnalyticsEvent {
        case methodSelected  = "Add Money: Method Selected"
        case amountConfirmed = "Add Money: Amount Confirmed"
        case paymentInvoked  = "Add Money: Payment Invoked"
        case terminal        = "Add Money"
    }

    /// Where the user entered the Add Money flow, sent as the `Source` of Add Money: Opened.
    enum AddMoneySource {
        case menu
        case giveShortfall
        case buyShortfall
        case usernameShortfall
        case chat
        case scanner
        case balance

        /// The shared contract's `Source` value for this entry point.
        var shared: SharedCoreKit.AddMoneySource {
            switch self {
            case .menu:              .menu
            case .giveShortfall:     .giveShortfall
            case .buyShortfall:      .buyShortfall
            case .usernameShortfall: .usernameShortfall
            case .chat:              .chat
            case .scanner:           .scanner
            case .balance:           .balance
            }
        }
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

// MARK: - Onramp -

extension Analytics {
    /// An onramp verification screen was shown.
    static func onrampStep(_ step: OnrampStep) {
        track(OnrampEvents.shared.step(step: step.shared))
    }
}

// MARK: - Phone & Onboarding -

extension Analytics {
    /// The user submitted a phone number for verification.
    static func phoneNumberEntered() {
        track(AccountEvents.shared.enteredPhoneNumber())
    }

    /// The user confirmed a phone number with its code.
    static func phoneNumberVerified() {
        track(AccountEvents.shared.verifiedPhoneNumber())
    }

    /// A verified phone number was linked to the account.
    static func phoneNumberLinked() {
        track(AccountEvents.shared.linkedPhoneNumber())
    }

    /// The user finished onboarding and was logged in.
    static func onboardingCompleted() {
        track(event: GeneralEvent.completeOnboarding)
    }
}

// MARK: - Tip Card -

extension Analytics {
    /// A tip card code was scanned.
    static func tipCardScanned() {
        track(ScanEvents.shared.tipCardScanned())
    }

    /// A scanned tip card resolved and was presented.
    static func tipCardPresented() {
        track(ScanEvents.shared.tipCardPresented())
    }
}

// MARK: - Gallery Scan -

extension Analytics {
    /// A picked image is about to be searched.
    static func galleryScanStarted() {
        track(ScanEvents.shared.galleryImagePicked())
    }

    /// A Kik code was found, and how deep in the ladder it was. The tier and zoom are the
    /// reason these events exist: the ladder's constants were inherited without ever being
    /// measured, and a tier distribution is what would justify or shrink them.
    static func galleryScanFoundCode(tier: String, zoom: Double, elapsed: TimeInterval) {
        track(
            event: GalleryScanEvent.codeFound,
            properties: [
                .type:    "Kik",
                .tier:    tier,
                .zoom:    zoom,
                .elapsed: elapsed,
            ]
        )
    }

    /// A QR code was found. No tier: QR is a single pass over the whole image.
    static func galleryScanFoundQR(elapsed: TimeInterval) {
        track(
            event: GalleryScanEvent.codeFound,
            properties: [
                .type:    "QR",
                .elapsed: elapsed,
            ]
        )
    }

    /// Nothing usable was found, and how long that took. A search that ran out of ladder is
    /// a different fact from one that ran out of time.
    static func galleryScanFoundNothing(reason: GalleryScanMiss, elapsed: TimeInterval) {
        track(
            event: GalleryScanEvent.nothingFound,
            properties: [
                .state:   reason.rawValue,
                .elapsed: elapsed,
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
    /// A bill grab started.
    static func grabBillStarted() {
        track(TransferEvents.shared.grabBillStart())
    }

    /// A bill give started.
    static func giveBillStarted() {
        track(TransferEvents.shared.giveBillStart())
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

// MARK: - Display Name -

extension Analytics {
    /// Which of the two display-name events a submission is. Split out from
    /// `displayNameSubmitted` so the rule is testable without the transport.
    static func displayNameEvent(hadPreviousName: Bool) -> DisplayNameEvent {
        hadPreviousName ? .updated : .set
    }

    /// A successful `SetDisplayName`. `hadPreviousName` is read *before* the RPC —
    /// after it, every submission looks like a replacement.
    static func displayNameSubmitted(source: DisplayNameSource, hadPreviousName: Bool) {
        switch displayNameEvent(hadPreviousName: hadPreviousName) {
        case .set:     track(DisplayNameEvents.shared.set(source: source.shared))
        case .updated: track(DisplayNameEvents.shared.updated(source: source.shared))
        }
    }
}

extension Analytics.DisplayNameSource {
    /// The shared contract's source for this surface.
    var shared: SharedCoreKit.DisplayNameSource {
        switch self {
        case .onboarding:   .onboarding
        case .myAccount:    .myAccount
        case .tipCardSetup: .tipCardSetup
        }
    }
}

// MARK: - Conversation -

extension Analytics {
    /// A chat message send. `Chat Type` mirrors Android — Tip / Contact /
    /// Unknown (a conversation not resolved locally yet).
    static func sentMessage(chatType: ConversationType?, error: Error? = nil) {
        track(ChatEvents.shared.sentMessage(chatType: chatType.sharedChatType, error: nil), error: error)
    }

    /// An inbound tipped Cash message the user has now read. Mutually exclusive with
    /// `messageReceived` — a tip reports only as a tip.
    static func tipReceived(chatType: ConversationType?, exchangedFiat: ExchangedFiat) {
        var properties = amountProperties(exchangedFiat)
        properties[.chatType] = chatType.analyticsValue
        track(event: ConversationEvent.tipReceived, properties: properties)
    }

    /// An inbound non-tip message the user has now read.
    static func messageReceived(chatType: ConversationType?) {
        track(ChatEvents.shared.messageReceived(chatType: chatType.sharedChatType))
    }
}

private extension Optional where Wrapped == ConversationType {
    /// The `Chat Type` property value, shared verbatim with Android.
    var analyticsValue: String {
        switch self {
        case .contactDm: "Contact"
        case .tipDm:     "Tip"
        case .group:     "Group"
        case .none:      "Unknown"
        }
    }

    /// The shared contract's `Chat Type`, which names the same four values.
    var sharedChatType: ChatType {
        switch self {
        case .contactDm: .contact
        case .tipDm:     .tip
        case .group:     .group
        case .none:      .unknown
        }
    }
}

// MARK: - Add Money -

extension Analytics {
    static func addMoneyOpened(source: AddMoneySource) {
        track(AddMoneyEvents.shared.opened(source: source.shared))
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
        track(AddMoneyEvents.shared.addressCopied(mint: mint.base58))
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
        switch event {
        case .openedFromDeeplink:
            track(TokenInfoEvents.shared.opened(source: .deeplink, mint: mint.base58))
        case .openedFromWallet:
            track(TokenInfoEvents.shared.opened(source: .wallet, mint: mint.base58))
        case .openedFromGive:
            track(event: NativeTokenInfoEvent.openedFromGive, properties: [.mint: mint.base58])
        case .openedFromSend:
            track(event: NativeTokenInfoEvent.openedFromSend, properties: [.mint: mint.base58])
        }
    }
}

// MARK: - Token Transactions -

extension Analytics {
    /// `Mint` is the token being purchased; `Payment Mint` is the token the
    /// buyer spent (USDF for reserves buys), taken from `exchangedFiat`.
    /// A nil `targetMint` omits `Mint` — `exchangedFiat` is payment-denominated,
    /// so no truthful substitute exists.
    static func tokenPurchase(method: TokenTransactionEvent, targetMint: PublicKey?, exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        var properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
            .paymentMint: exchangedFiat.mint.base58,
            .fiat: exchangedFiat.nativeAmount.doubleValue,
            .currency: exchangedFiat.currencyRate.currency.rawValue,
        ]
        if let targetMint {
            properties[.mint] = targetMint.base58
        }
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
    /// `Mint` is the launched currency; `Payment Mint` is the token that paid
    /// the launch cost.
    static func currencyLaunch(event: CurrencyLaunchEvent, launchedMint: PublicKey, paymentMint: PublicKey, exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        let properties: [Property: AnalyticsValue] = [
            .state: successful ? String.success : String.failure,
            .mint: launchedMint.base58,
            .paymentMint: paymentMint.base58,
            .fiat: exchangedFiat.nativeAmount.doubleValue,
            .currency: exchangedFiat.currencyRate.currency.rawValue,
        ]
        track(event: event, properties: properties, error: error)
    }
}

// MARK: - Deeplinks -

extension Analytics {
    static func deeplinkOpened(url: URL) {
        track(DeeplinkEvents.shared.open(url: url.sanitizedForAnalytics))
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

        case ownerPublicKey    = "Owner Public Key"
        case grabTime          = "Grab Time"

        case state             = "State"
        case method            = "Method"
        case quarks            = "Quarks"
        case mint              = "Mint"
        case paymentMint       = "Payment Mint"
        case tokenSymbol       = "Token Symbol"
        case paymentTokenSymbol = "Payment Token Symbol"
        case fiat              = "Fiat"
        case currency          = "Currency"
        case fx                = "Exchange Rate"

        case type              = "Type"
        case chatType          = "Chat Type"
        case error             = "Error"

        case tier              = "Tier"
        case zoom              = "Zoom"
        case elapsed           = "Elapsed"

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
