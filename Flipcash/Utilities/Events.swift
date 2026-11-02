//
//  Events.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import FlipcashCore
import SharedCore

// MARK: - Domain Event Enums -

extension Analytics {
    /// A tapped button, built by the shared contract.
    enum ButtonEvent {
        case createAccount
        case saveAccessKey
        case wroteAccessKey
        case allowPush
        case skipPush
        case buyWithReserves
        case buyWithCurrency
        case buyWithCoinbase
        case buyWithPhantom
        case give
        case shareTokenInfo
    }

    enum TransferEvent: String, AnalyticsEvent {
        case withdrawal      = "Withdrawal"
        case sentTip         = "Sent Tip"
        case sendCashLink    = "Send Cash Link"
        case receiveCashLink = "Receive Cash Link"
        case grabBill        = "Grab Bill"
        case giveBill        = "Give Bill"
    }

    /// An onramp verification screen, sent as `Onramp: Show <step>`.
    enum OnrampStep {
        case showInfo
        case enterPhone
        case confirmPhone
        case enterEmail
        case confirmEmail

        /// The shared contract's step for this screen.
        var shared: SharedCoreKit.OnrampStep {
            switch self {
            case .showInfo:     .showInfo
            case .enterPhone:   .enterPhone
            case .confirmPhone: .confirmPhone
            case .enterEmail:   .enterEmail
            case .confirmEmail: .confirmEmail
            }
        }
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

    /// Why a gallery scan came back with nothing. `cancelled` covers both the user tapping
    /// Cancel and the budget running out, which are the same event from the search's side.
    enum GalleryScanMiss {
        case exhausted
        case cancelled
        case routeRefused

        /// The shared `Exhausted` flag: true when the search was stopped before the ladder ended.
        /// The shared event has no separate user-cancel value, so a Cancel tap reports true too.
        var stoppedEarly: Bool { self == .cancelled }
    }

    enum WalletEvent: String, AnalyticsEvent {
        case connect               = "Wallet: Connect"
        case requestAmount         = "Wallet: Request Amount"
        case cancel                = "Wallet: Cancel"
    }

    /// Where Token Info was opened from, built by the shared contract.
    enum TokenInfoEvent {
        case openedFromDeeplink
        case openedFromWallet
        case openedFromDiscovery
        case openedFromSearch
        case openedFromChat
        case openedFromGive
        case openedFromSend
    }

    enum TokenTransactionEvent: String, AnalyticsEvent {
        case purchaseWithReserves = "Token Purchase With Reserves"
        case purchaseWithCurrency = "Token Purchase With Currency"
        case sell                 = "Token Sell"
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
        switch name {
        case .createAccount:   track(ButtonEvents.shared.tapped(button: .createAccount))
        case .saveAccessKey:   track(ButtonEvents.shared.tapped(button: .saveAccessKey))
        case .wroteAccessKey:  track(ButtonEvents.shared.tapped(button: .wroteAccessKey))
        case .allowPush:       track(ButtonEvents.shared.tapped(button: .allowPush))
        case .skipPush:        track(ButtonEvents.shared.tapped(button: .skipPush))
        case .buyWithReserves: track(ButtonEvents.shared.tapped(button: .buyWithReserves))
        case .shareTokenInfo:  track(ButtonEvents.shared.tapped(button: .shareTokenInfo))
        case .buyWithCurrency: track(ButtonEvents.shared.tapped(button: .buyWithCurrency))
        case .buyWithCoinbase: track(ButtonEvents.shared.tapped(button: .buyWithCoinbase))
        case .buyWithPhantom:  track(ButtonEvents.shared.tapped(button: .buyWithPhantom))
        case .give:            track(ButtonEvents.shared.tapped(button: .give))
        }
    }
}

// MARK: - Account -

extension Analytics {
    /// The user chose to create an account and registration began.
    static func createAccount() {
        track(AccountEvents.shared.createAccount())
    }

    /// A saved account logged in at launch with no action from the user.
    static func autoLoginComplete() {
        track(AccountEvents.shared.autoLoginComplete())
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
        track(AccountEvents.shared.completeOnboarding())
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

    /// A code was found, and how deep in the ladder it was. The tier and zoom are the reason
    /// this event exists: the ladder's constants were inherited without ever being measured, and
    /// a tier distribution is what would justify or shrink them.
    static func galleryScanFoundCode(tier: StillImageCodeSearch.Tier, zoom: Double, elapsed: TimeInterval) {
        track(ScanEvents.shared.gallerySucceeded(tier: galleryTier(tier), zoom: zoom, timeMillis: milliseconds(elapsed)))
    }

    /// A QR code was found. QR is a single pass over the whole image, so it reports the first
    /// tier at zoom 1. The shared event has no Kik or QR type, so the two are no longer told apart.
    static func galleryScanFoundQR(elapsed: TimeInterval) {
        track(ScanEvents.shared.gallerySucceeded(tier: galleryTier(.wholeImage), zoom: 1, timeMillis: milliseconds(elapsed)))
    }

    /// Nothing usable was found, and how long that took.
    static func galleryScanFoundNothing(reason: GalleryScanMiss, elapsed: TimeInterval) {
        track(ScanEvents.shared.galleryFailed(timeMillis: milliseconds(elapsed), exhausted: reason.stoppedEarly))
    }

    /// The shared `Tier`: the rung of the crop ladder that decoded, 1 to 3.
    static func galleryTier(_ tier: StillImageCodeSearch.Tier) -> Int32 {
        switch tier {
        case .wholeImage: 1
        case .quadrant:   2
        case .window:     3
        }
    }

    /// The shared events carry durations in milliseconds.
    static func milliseconds(_ interval: TimeInterval) -> Int64 {
        Int64((interval * 1000).rounded())
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

extension ExchangedFiat {
    /// The shared contract's amount block. USDC is the USDF value, which Android always sends.
    var analyticsAmount: AnalyticsAmount {
        AnalyticsAmount(
            fiat: nativeAmount.doubleValue,
            currency: currencyRate.currency.rawValue,
            usdc: usdfValue.doubleValue,
            quarks: Int64(clamping: onChainAmount.quarks),
            exchangeRate: KotlinDouble(double: currencyRate.fx.analyticsValue),
            mint: mint.base58
        )
    }
}

extension FiatAmount {
    /// The shared contract's amount block for a fiat-only amount, as Android builds it: no rate or
    /// mint, with `USDC` repeating the amount and `Quarks` at six decimals.
    var analyticsAmount: AnalyticsAmount {
        AnalyticsAmount(
            fiat: doubleValue,
            currency: currency.rawValue,
            usdc: doubleValue,
            quarks: Int64((doubleValue * 1_000_000).rounded()),
            exchangeRate: nil,
            mint: nil
        )
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

    /// Cash was sent, or a request share was paid. `error` is nil on success. `recipientCount`
    /// is for `.groupSend` only.
    static func sentCash(exchangedFiat: ExchangedFiat, context: SendContext, recipientCount: Int? = nil, error: Error?) {
        track(
            TransferEvents.shared.sentCash(
                state: .from(error),
                amount: exchangedFiat.analyticsAmount,
                error: nil,
                context: context,
                recipientCount: recipientCount.map { KotlinInt(int: Int32(clamping: $0)) }
            ),
            error: error
        )
    }

    /// A reaction boost was paid for. `exchangedFiat` is the whole boost, before the split.
    /// `error` is nil on success.
    static func sentBoost(chatType: ConversationType?, exchangedFiat: ExchangedFiat, error: Error?) {
        track(
            TransferEvents.shared.sentBoost(
                chatType: chatType.sharedChatType,
                state: .from(error),
                amount: exchangedFiat.analyticsAmount,
                error: nil
            ),
            error: error
        )
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

// MARK: - Profile -

extension Analytics {
    /// The Settings screen was opened from the You tab.
    static func profileSettingsViewed() {
        track(ProfileEvents.shared.settingsViewed())
    }

    /// The Edit Profile screen was opened from the You tab.
    static func profileEditProfileViewed() {
        track(ProfileEvents.shared.editProfileViewed())
    }

    /// A profile field was saved on the server.
    static func profileFieldSaved(_ field: SharedCoreKit.ProfileField) {
        track(ProfileEvents.shared.fieldSaved(field: field))
    }

    /// The server refused a bio for moderation.
    static func profileBioModerationFailed() {
        track(ProfileEvents.shared.bioModerationFailed())
    }

    /// An entry was picked in another user's profile menu.
    static func profileMenuAction(_ action: SharedCoreKit.ProfileMenuAction) {
        track(ProfileEvents.shared.menuAction(action: action))
    }

    /// An entry was picked in another user's profile menu; entries outside the catalogue send nothing.
    static func profileMenuAction(for item: ProfileMenuItem) {
        guard let action = item.analyticsAction else { return }
        profileMenuAction(action)
    }

    /// The pinned button under another user's profile was tapped.
    static func profilePinnedButtonTapped(_ action: SharedCoreKit.ProfilePinnedAction) {
        track(ProfileEvents.shared.pinnedButtonTapped(action: action))
    }

    /// The pinned button was tapped; an empty pin sends nothing.
    static func profilePinnedButtonTapped(for action: ProfilePinnedAction) {
        guard let shared = action.analyticsAction else { return }
        profilePinnedButtonTapped(shared)
    }

    /// The profile card appeared.
    static func profileCardShown() {
        track(ProfileEvents.shared.cardShown())
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

    /// `MuteChat` returned; `error` is nil on success.
    static func chatMuted(chatType: ConversationType?, duration: MuteDuration, error: Error?) {
        track(ChatEvents.shared.muted(
            chatType: chatType.sharedChatType,
            duration: duration,
            state: .from(error),
            error: error.map(chatResult)
        ))
    }

    /// `UnmuteChat` returned; `error` is nil on success.
    static func chatUnmuted(chatType: ConversationType?, error: Error?) {
        track(ChatEvents.shared.unmuted(
            chatType: chatType.sharedChatType,
            state: .from(error),
            error: error.map(chatResult)
        ))
    }
}

// MARK: - Group -

extension Analytics {
    /// The New Group form opened from the New Chat row of this `type`.
    static func groupNewOpened(type: GroupType) {
        track(GroupEvents.shared.doNewOpened(type: type))
    }

    /// `StartChat` returned for a new group; `error` is nil on success.
    static func groupCreated(error: Error?, rules: ConversationRules?, hasPicture: Bool) {
        track(GroupEvents.shared.created(
            state: .from(error),
            error: error.map(chatResult),
            gateMint: rules.gateMint?.base58,
            hasPicture: hasPicture
        ))
    }

    /// `EditChat` returned after a rename or a picture change; `error` is nil on success.
    static func groupEdited(field: GroupField, error: Error?) {
        track(GroupEvents.shared.edited(field: field, state: .from(error), error: error.map(chatResult)))
    }

    /// The invite sheet was presented.
    static func groupInviteSheetOpened(source: GroupInviteSheetSource, memberCount: UInt64) {
        track(GroupEvents.shared.inviteSheetOpened(source: source, memberCount: Int32(clamping: memberCount)))
    }

    /// The invite link left the app through the share sheet or the pasteboard.
    static func groupInviteShared(method: GroupInviteMethod) {
        track(GroupEvents.shared.inviteShared(method: method))
    }

    /// The group card appeared.
    static func groupCardShown(memberCount: UInt64) {
        track(GroupEvents.shared.cardShown(memberCount: Int32(clamping: memberCount)))
    }

    /// A group opened from an invite.
    static func groupInviteFollowed(source: GroupInviteSource) {
        track(GroupEvents.shared.inviteFollowed(source: source))
    }

    /// The gate first appeared during a visit to a group.
    static func groupGateShown(access: GroupAccess, gateMint: PublicKey?, memberCount: UInt64) {
        track(GroupEvents.shared.gateShown(
            access: access,
            gateMint: gateMint?.base58,
            memberCount: Int32(clamping: memberCount)
        ))
    }

    /// A funding button on the gate was tapped.
    static func groupGateFundingTapped(method: GroupGateFunding, gateMint: PublicKey?) {
        track(GroupEvents.shared.gateFundingTapped(method: method, gateMint: gateMint?.base58))
    }

    /// `JoinChat` returned; `error` is nil on success.
    static func groupJoined(error: Error?, memberCount: UInt64, gated: Bool) {
        track(GroupEvents.shared.joined(
            state: .from(error),
            error: error.map(chatResult),
            memberCount: Int32(clamping: memberCount),
            gated: gated
        ))
    }

    /// `LeaveChat` returned; `error` is nil on success.
    static func groupLeft(error: Error?, memberCount: UInt64) {
        track(GroupEvents.shared.left(
            state: .from(error),
            error: error.map(chatResult),
            memberCount: Int32(clamping: memberCount)
        ))
    }

    /// The group info screen opened.
    static func groupInfoOpened(memberCount: UInt64, isMember: Bool) {
        track(GroupEvents.shared.infoOpened(memberCount: Int32(clamping: memberCount), isMember: isMember))
    }

    /// `CreateInvite` returned; `error` is nil on success.
    static func groupInviteLinkCreated(error: Error?) {
        track(GroupEvents.shared.inviteLinkCreated(state: .from(error), error: error.map(chatResult)))
    }

    /// `RevokeInvite` returned after the host confirmed; `error` is nil on success.
    static func groupInviteLinkRevoked(error: Error?) {
        track(GroupEvents.shared.inviteLinkRevoked(state: .from(error), error: error.map(chatResult)))
    }

    /// `AdmitLobbyMember` returned; `error` is nil on success.
    static func groupJoinRequestApproved(error: Error?) {
        track(GroupEvents.shared.joinRequestApproved(state: .from(error), error: error.map(chatResult)))
    }

    /// `DenyLobbyMember` returned; `error` is nil on success.
    static func groupJoinRequestDenied(error: Error?) {
        track(GroupEvents.shared.joinRequestDenied(state: .from(error), error: error.map(chatResult)))
    }

    /// `SilenceUser` returned; `error` is nil on success.
    static func groupMemberSilenced(duration: SilenceDuration, error: Error?) {
        track(GroupEvents.shared.memberSilenced(duration: duration.shared, state: .from(error), error: error.map(chatResult)))
    }

    /// `BanUser` returned after the host confirmed removal; `error` is nil on success.
    static func groupMemberRemoved(error: Error?) {
        track(GroupEvents.shared.memberRemoved(state: .from(error), error: error.map(chatResult)))
    }

    /// The `Error` value the group and mute events send: the chat RPC's result as the proto names
    /// it, or `Network` for anything the server didn't answer with a result.
    ///
    /// iOS folds an unrecognized result into the same `.unknown` case as an unclassified RPC
    /// failure, so `.unknown` reports as `Network`, the more common of the two.
    static func chatResult(_ error: Error) -> String {
        switch error {
        case let error as ErrorStartChat:
            switch error {
            case .denied:                                         "Denied"
            case .titleModerated:                                 "TitleModerated"
            case .pictureBlobNotAccepted:                         "PictureBlobNotAccepted"
            case .coverPictureBlobNotAccepted:                    "CoverPictureBlobNotAccepted"
            case .invalidRules:                                   "InvalidRules"
            case .rulesNotSatisfied:                              "RulesNotSatisfied"
            case .descriptionModerated:                           "DescriptionModerated"
            case .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorEditChat:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .titleModerated:                                 "TitleModerated"
            case .pictureBlobNotAccepted:                         "PictureBlobNotAccepted"
            case .coverPictureBlobNotAccepted:                    "CoverPictureBlobNotAccepted"
            case .descriptionModerated:                           "DescriptionModerated"
            case .invalidRules:                                   "InvalidRules"
            case .rulesNotSatisfied:                              "RulesNotSatisfied"
            case .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorJoinChat:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .rulesNotSatisfied:                              "RulesNotSatisfied"
            case .banned:                                         "Banned"
            case .inviteNotFound:                                 "InviteNotFound"
            case .inviteExhausted:                                "InviteExhausted"
            case .inviteExpired:                                  "InviteExpired"
            case .inviteRevoked:                                  "InviteRevoked"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorLeaveChat:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorMuteChat:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorUnmuteChat:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorCreateInvite:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .invalidExpiresAt:                               "InvalidExpiresAt"
            case .tooManyInvites:                                 "TooManyInvites"
            case .invalidSignature:                               "InvalidSignature"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorRevokeInvite:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorAdmitLobbyMember:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .notInLobby:                                     "NotInLobby"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorDenyLobbyMember:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorSilenceUser:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .cannotRestrictCreator:                          "CannotRestrictCreator"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        case let error as ErrorBanUser:
            switch error {
            case .denied:                                         "Denied"
            case .notFound:                                       "NotFound"
            case .cannotRestrictCreator:                          "CannotRestrictCreator"
            case .ok, .unknown, .transportFailure, .cancelled, .rejected: "Network"
            }
        default:
            "Network"
        }
    }
}

extension SilenceDuration {
    /// The shared contract's `Duration` for this choice.
    var shared: SharedCoreKit.SilenceDuration {
        switch self {
        case .oneHour:    .oneHour
        case .eightHours: .eightHours
        case .oneWeek:    .oneWeek
        case .forever:    .forever
        }
    }
}

private extension EventState {
    /// `Success` when there was no error.
    static func from(_ error: Error?) -> EventState {
        error == nil ? .success : .failure
    }
}

extension Optional where Wrapped == ConversationRules {
    /// The `Gate Mint` property: the one mint the listener balance rule names, or nil when the
    /// group has no token gate — no rule, or a rule every holding counts toward.
    var gateMint: PublicKey? {
        for case .minimumBalance(let requirement) in self?.listener ?? [] {
            return requirement.mints.count == 1 ? requirement.mints[0] : nil
        }
        return nil
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
        case .openedFromDiscovery:
            track(TokenInfoEvents.shared.opened(source: .discovery, mint: mint.base58))
        case .openedFromSearch:
            track(TokenInfoEvents.shared.opened(source: .search, mint: mint.base58))
        case .openedFromChat:
            track(TokenInfoEvents.shared.opened(source: .chat, mint: mint.base58))
        case .openedFromGive:
            track(TokenInfoEvents.shared.opened(source: .give, mint: mint.base58))
        case .openedFromSend:
            track(TokenInfoEvents.shared.opened(source: .send, mint: mint.base58))
        }
    }

    /// An action tile on Currency Info was tapped, before anything opens.
    static func tokenInfoTileTapped(tile: CurrencyInfoActions.Tile, mint: PublicKey) {
        track(TokenInfoEvents.shared.tileTapped(tile: tile.shared, mint: mint.base58))
    }

    /// A row of the More sheet was picked and is about to run.
    static func tokenInfoMoreOptionPicked(row: CurrencyInfoActions.MoreRow, mint: PublicKey) {
        track(TokenInfoEvents.shared.moreOptionPicked(option: row.shared, mint: mint.base58))
    }

    /// A community chat was tapped on Currency Info or its View All list.
    static func tokenInfoCommunityChatTapped(mint: PublicKey) {
        track(TokenInfoEvents.shared.communityChatTapped(mint: mint.base58))
    }
}

extension CurrencyInfoActions.Tile {
    /// The shared contract's tile.
    var shared: CurrencyInfoTile {
        switch self {
        case .send:         .send
        case .buy:          .buy
        case .buyIn:        .buyIn
        case .transactions: .transactions
        case .more:         .more
        }
    }
}

extension CurrencyInfoActions.MoreRow {
    /// The shared contract's More option.
    var shared: CurrencyInfoMoreOption {
        switch self {
        case .convert:  .convert
        case .withdraw: .withdraw
        case .deposit:  .deposit
        }
    }
}

// MARK: - Search -

extension Analytics {
    /// The Chats search screen was shown.
    static func searchOpened() {
        track(SearchEvents.shared.opened())
    }

    /// A search result row was tapped, at the tap.
    static func searchResultTapped(_ type: SearchResultType) {
        track(SearchEvents.shared.resultTapped(resultType: type))
    }
}

// MARK: - Payment Requests -

extension Analytics {
    /// `CreateRequest` returned, once per confirm. `amount` is the per-person amount and
    /// `payerCount` the people asked, the creator excluded. `error` is nil on success.
    static func paymentRequestCreated(payerCount: Int, amount: FiatAmount, error: Error?) {
        track(
            PaymentRequestEvents.shared.created(
                payerCount: Int32(clamping: payerCount),
                state: .from(error),
                amount: amount.analyticsAmount,
                error: nil
            ),
            error: error
        )
    }

    /// The creator closed a request early and the call returned. `error` is nil on success.
    static func paymentRequestClosed(error: Error?) {
        track(PaymentRequestEvents.shared.closed(state: .from(error), error: nil), error: error)
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

    /// A buy submitted, sent as `Token Purchase With {method}`. `mint` is the token bought and
    /// `amount` the net purchase in the user's currency, as Android sends it. `error` is nil
    /// when the submit succeeded.
    static func tokenPurchase(method: SharedCoreKit.PurchaseMethod, mint: PublicKey, amount: FiatAmount, error: Error?) {
        track(
            SwapEvents.shared.purchase(method: method, mint: mint.base58, amount: amount.analyticsAmount, error: nil),
            error: error
        )
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
    static func currencyLaunch(method: LaunchMethod, launchedMint: PublicKey, paymentMint: PublicKey, exchangedFiat: ExchangedFiat, successful: Bool, error: Error? = nil) {
        track(
            CurrencyLaunchEvents.shared.launched(
                method: method,
                state: successful ? .success : .failure,
                mint: launchedMint.base58,
                paymentMint: paymentMint.base58,
                fiat: exchangedFiat.nativeAmount.doubleValue,
                currency: exchangedFiat.currencyRate.currency.rawValue,
                error: nil
            ),
            error: error
        )
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

    /// A scanned QR code that isn't a Flipcash link, as Android's scanner reports it. Query and
    /// fragment are stripped, so no token or key in them reaches analytics.
    static func deeplinkParseFailed(url: URL) {
        track(DeeplinkEvents.shared.parseFailed(url: url.sanitizedForAnalytics))
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
