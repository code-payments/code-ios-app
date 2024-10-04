//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2021-01-21.
//

import Foundation
import Combine
import CodeUI
import CodeServices
import SwiftUI

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published var isShowingPushPrompt: Bool = false
    
    @Published private(set) var hasBalance: Bool = false
    @Published private(set) var currentBalance: Kin = 0
//    @Published private(set) var billState: BillState = .default()
    @Published private(set) var presentationState: PresentationState = .hidden(.slide)
    
//    @Published private(set) var phoneLink: PhoneLink?
    
    weak var delegate: SessionDelegate?
    
    let twitterUserController: TwitterUserController
    let tipController: TipController
    let chatController: ChatController
    
    let organizer: Organizer
    
    private(set) var user: User
    
    private let client: Client
    private let exchange: Exchange
    private let bannerController: BannerController
    private let betaFlags: BetaFlags

    private let flowController: FlowController
    private let giftCardVault: GiftCardVault
    
    private var scannedRendezvous: Set<PublicKey> = []
    private var cancellables: Set<AnyCancellable> = []
    
//    private var receiveTransaction: ReceiveTransaction?
//    private var sendTransaction: SendTransaction?
    
    private let timeoutInterval: TimeInterval = 50.0
    private var timeoutCancelItem: DispatchWorkItem?
    
    private var billQueue: [Bill] = []
    
    private var balancePoller: Poller!
    
    /// We use a queue to schedule any work that needs
    /// to be delayed until after we have sufficient
    /// account info and balance from a fetchBalance()
    private let balanceQueue = Queue(isBlocked: true)
    
    private var confirmationBannerID: UUID?
    
    // MARK: - Init -
    
    init(organizer: Organizer, user: User, client: Client, exchange: Exchange, bannerController: BannerController, betaFlags: BetaFlags) {
        self.organizer = organizer
        self.user = user
        self.client = client
        self.exchange = exchange
        self.bannerController = bannerController
        self.betaFlags = betaFlags
        
        self.twitterUserController = TwitterUserController(owner: organizer.ownerKeyPair, client: client)
        self.tipController = TipController(organizer: organizer, client: client, bannerController: bannerController)
        self.chatController = ChatController(client: client, organizer: organizer)
        
        self.flowController = FlowController(client: client, organizer: organizer)
        self.giftCardVault = GiftCardVault()
        
        self.tipController.delegate = self
        
        registerPoller()
        
        poll()
        
        chatController.fetchChats()
        
        Task {
//            try? await updatePhoneLinkStatus()
            try? await updateUserInfo()
//            try? await updateUserPreferences()
            
            // Must be after user info
//            try await receiveFirstKinIfAvailable()
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating Session")
    }
    
    func prepareForLogout() {
        tipController.prepareForLogout()
    }
    
    // MARK: - User -
    
    func updateUserInfo() async throws {
        guard let phone = user.phone else {
            return
        }
        
        let user = try await client.fetchUser(
            phone: phone,
            owner: organizer.ownerKeyPair
        )
        
        self.user = user
    }
    
    private func updateUserPreferences() async throws {
        try await client.updatePreferences(
            user: user,
            locale: .current,
            owner: organizer.ownerKeyPair
        )
    }
    
    // MARK: - Poller -
    
    private func registerPoller() {
        self.balancePoller = Poller(seconds: 10) { [weak self] in
            self?.poll()
        }
    }
    
    private func poll() {
        if flowController.areLimitsStale {
            flowController.updateLimits()
        }
        
        updateBalance()
        fetchPrivacyUpgrades()
    }
    
    // MARK: - Privacy Upgrade -
    
    private func fetchPrivacyUpgrades() {
        let client = self.client
        let mnemonic = organizer.mnemonic
        Task {
            let upgradeableIntents = try await client.fetchUpgradeableIntents(owner: organizer.ownerKeyPair)
            await withThrowingTaskGroup(of: Void.self) { group in
                for upgradeableIntent in upgradeableIntents {
                    group.addTask {
                        do {
                            try await client.upgradePrivacy(
                                mnemonic: mnemonic,
                                upgradeableIntent: upgradeableIntent
                            )
                            
                            Analytics.upgradePrivacy(
                                successful: true,
                                intentID: upgradeableIntent.id,
                                actionCount: upgradeableIntent.actions.count,
                                error: nil
                            )
                            
                        } catch {
                            Analytics.upgradePrivacy(
                                successful: false,
                                intentID: upgradeableIntent.id,
                                actionCount: upgradeableIntent.actions.count,
                                error: error
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Balance -
    
    private func fetchBalance() async throws {
        currentBalance = try await flowController.fetchBalance()
    }
    
    private func updateBalance() {
        Task {
            do {
                try await fetchBalance()
                
                if organizer.isUnuseable {
                    delegate?.didDetectUnlockedAccount()
                }
                
                balanceQueue.setUnblocked()
                hasBalance = true
                
            } catch ErrorFetchAccountInfos.migrationRequired {
                Analytics.migrationRequired()
            }
        }
    }
    
    func receiveIfNeeded() {
        Task {
            try await flowController.receiveIfNeeded()
        }
    }
    
    func initiateSwap() async throws {
        try await fetchBalance()
    }
    
    // MARK: - Phone Link  -
    
    func unlinkAccount(from phone: Phone) async throws {
        try await client.unlinkAccount(phone: phone, owner: organizer.ownerKeyPair)
    }
    
//    func updatePhoneLinkStatus() async throws {
//        phoneLink = try await client.fetchAssociatedPhoneNumber(owner: organizer.ownerKeyPair)
//    }
    
    // MARK: - Push -
    
    private func promptForPushPermissionsIfNeeded() {
        Task {
            if await tipController.shouldPromptForPushPermissions() {
                try await Task.delay(milliseconds: 500)
                isShowingPushPrompt = true
                tipController.setPushPrompted()
            }
        }
    }
    
    // MARK: - Chat -
    
    func payAndStartChat(amount: KinAmount, destination: PublicKey, chatID: ChatID) async throws -> Chat {
        let rendezvous = PublicKey.generate()!
        
        do {
            try await flowController.transfer(
                amount: amount,
                fee: 0,
                additionalFees: [],
                rendezvous: rendezvous,
                destination: destination,
                withdrawal: true,
                tipAccount: nil,
                chatID: chatID
            )
            
            let chat = try await client.startChat(
                owner: organizer.ownerKeyPair,
                intentID: rendezvous, // In this case, rendezvous must be the transfer intent ID
                destination: destination
            )
            
            return chat
//            Analytics.transferForTip(
//                amount: amount,
//                successful: true,
//                error: nil
//            )
            
        } catch {
//            Analytics.transferForTip(
//                amount: amount,
//                successful: false,
//                error: error
//            )
            
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: rendezvous,
                tray: organizer.tray,
                amount: amount
            )
            
            throw error
        }
    }
    
    // MARK: - Send -
    
    func hasSufficientFunds(for amount: KinAmount) -> Bool {
        currentBalance >= amount.kin
    }
    
    func hasAvailableDailyLimit() -> Bool {
        sendLimitFor(currency: .usd).nextTransaction > 0
    }
    
    func hasAvailableTransactionLimit(for amount: KinAmount) -> Bool {
        sendLimitFor(currency: amount.rate.currency).nextTransaction >= amount.fiat
    }
    
    func sendLimitFor(currency: CurrencyCode) -> SendLimit {
        flowController.limits?.sendLimitFor(currency: currency) ?? .zero
    }
    
    func buyLimit(for currency: CurrencyCode) -> BuyLimit? {
        flowController.limits?.buyLimit(for: currency)
    }
    
    // MARK: - Errors -
    
    private func showNoCodeFoundError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.noCodeFound,
            description: Localized.Error.Description.noCodeFound,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showPaymentRequestError() {
        bannerController.show(
            style: .error,
            title: "Payment Failed",
            description: "This payment request could not be paid at this time. Please try again later.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showSendError() {
        bannerController.show(
            style: .error,
            title: "Transaction Failed",
            description: "This transaction could not be sent at this time. Please try again later.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showDeniedError() {
        bannerController.show(
            style: .error,
            title: "Transaction Denied",
            description: "This transaction could not be sent. The maximum transaction limit has been reached.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showConnectivityError(completion: @escaping VoidAction) {
        bannerController.show(
            style: .error,
            title: "No Internet Connection",
            description: "Please check your internet connection or try again later.",
            actions: [
                .standard(title: Localized.Action.ok, action: completion),
            ]
        )
    }
    
    private func showGiftCardClaimedError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.alreadyCollectedBySomeone,
            description: Localized.Error.Description.alreadyCollectedBySomeone,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showGiftCardExpiredError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.linkExpired,
            description: Localized.Error.Description.linkExpired,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showGiftCardCollectionFailedError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.failedToCollect,
            description: Localized.Error.Description.failedToCollect,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showCashExpiredError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.cashExpired,
            description: Localized.Error.Description.cashExpired,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showRemoteSendConfirmation(confirm: @escaping VoidAction, tryAgain: @escaping VoidAction, cancel: @escaping VoidAction) -> UUID {
        bannerController.show(
            style: .notification,
            title: Localized.Prompt.Title.didYouSendLink,
            description: Localized.Prompt.Description.didYouSendLink,
            position: .bottom,
            isDismissable: false,
            actions: [
                .prominent(title: Localized.Action.yes, action: confirm),
                .standard(title: Localized.Action.noTryAgain, action: tryAgain),
                .subtle(title: Localized.Action.cancelSend, action: cancel),
            ]
        )
    }
    
    // MARK: - Withdrawals -
    
    func fetchDestinationMetadata(destination: PublicKey) async -> DestinationMetadata {
        await client.fetchDestinationMetadata(destination: destination)
    }
    
    func withdrawExternally(amount: KinAmount, to destination: PublicKey) async throws {
        try await flowController.withdrawExternally(amount: amount, to: destination)
        updateBalance()
    }
}

extension Session: TipControllerDelegate {
    func willShowTipCard(for user: TwitterUser) {
//        presentMyTipCard(user: user)
    }
}

// MARK: - Errors -

extension Session {
    enum PaymentError: Swift.Error {
        case noExchangeData
        case invalidPayloadForRequest
        case exchangeForCurrencyNotFound
        case messageForRendezvousNotFound
        case rendezvousFailedValidation
    }
}

// MARK: - Bill -

extension Session {
    struct Bill {
        enum Kind {
            case cash
            case remote
            case firstKin
            case referral
        }
        
        var title: String {
            switch kind {
            case .cash, .remote, .firstKin:
                return Localized.Subtitle.youReceived
            case .referral:
                return Localized.Subtitle.referralBonusReceived
            }
        }
        
        let kind: Kind
        let amount: KinAmount
        let didReceive: Bool
        
        init(kind: Kind, amount: KinAmount, didReceive: Bool) {
            self.kind = kind
            self.amount = amount
            self.didReceive = didReceive
        }
    }
}

// MARK: - Gift Card -

extension GiftCardAccount {
    var url: URL {
        URL.send(with: mnemonic)
    }
}

// MARK: - Mock -

extension Session {
    static let mock = Session(
        organizer: .mock,
        user: .mock,
        client: .mock,
        exchange: .mock,
        bannerController: .mock,
        betaFlags: .mock
    )
}

extension Client {
    static let mock = Client(network: .testNet)
}

extension View {
    
    @MainActor
    func environmentObjectsForSession() -> some View {
        self
            .preferredColorScheme(.dark)
            .environmentObject(SessionAuthenticator.mock)
            .environmentObject(CameraAuthorizer())
            .environmentObject(Client.mock)
            .environmentObject(BannerController.mock)
            .environmentObject(Exchange.mock)
            .environmentObject(BetaFlags.shared)
    }
}

enum PresentationState: Equatable {
    
    enum Style {
        case pop
        case slide
    }
    
    case visible(Style)
    case hidden(Style)
    
    var isPresenting: Bool {
        switch self {
        case .visible: return true
        case .hidden:  return false
        }
    }
}
