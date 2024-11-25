//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2021-01-21.
//

import SwiftUI
import Combine
import CodeUI
import FlipchatServices

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published var isShowingPushPrompt: Bool = false
    
    @Published private(set) var hasBalance: Bool = false
    @Published private(set) var currentBalance: Kin = 0
    @Published private(set) var presentationState: PresentationState = .hidden(.slide)
    
    @Published private(set) var userFlags: UserFlags?
    
    var startGroupCost: Kin {
        userFlags?.startGroupCost ?? 201 // TODO: Fixed price
    }
    
    var startGroupDestination: PublicKey? {
        userFlags?.feeDestination
    }
    
    weak var delegate: SessionDelegate?
    
    let userID: UserID
    let organizer: Organizer
    
    private let client: Client
    private let flipClient: FlipchatClient
    private let exchange: Exchange
    private let banners: Banners
    private let betaFlags: BetaFlags

    private let flowController: FlowController
    
    private var scannedRendezvous: Set<PublicKey> = []
    private var cancellables: Set<AnyCancellable> = []
    
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
    
    init(userID: UserID, organizer: Organizer, client: Client, flipClient: FlipchatClient, exchange: Exchange, banners: Banners, betaFlags: BetaFlags) {
        self.userID = userID
        self.organizer = organizer
        self.client = client
        self.flipClient = flipClient
        self.exchange = exchange
        self.banners = banners
        self.betaFlags = betaFlags
        
        self.flowController = FlowController(
            client: client,
            organizer: organizer
        )
        
        registerPoller()
        fetchUserFlags()
        
        poll()
    }
    
    deinit {
        trace(.warning, components: "Deallocating Session")
    }
    
    func prepareForLogout() {
        
    }
    
    // MARK: - Flags -
    
    private func fetchUserFlags() {
        Task {
            let flags = try await flipClient.fetchUserFlags(
                userID: userID,
                owner: organizer.ownerKeyPair
            )
            
            if flags.isStaff {
                BetaFlags.shared.setAccessGranted(true)
            }
            
            userFlags = flags
        }
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
    
    // MARK: - Push -
    
//    private func promptForPushPermissionsIfNeeded() {
//        Task {
//            if await tipController.shouldPromptForPushPermissions() {
//                try await Task.delay(milliseconds: 500)
//                isShowingPushPrompt = true
//                tipController.setPushPrompted()
//            }
//        }
//    }
    
    // MARK: - Send -
    
    func hasSufficientFunds(for amount: Kin) -> Bool {
        currentBalance >= amount
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
    
    private func showPaymentRequestError() {
        banners.show(
            style: .error,
            title: "Payment Failed",
            description: "This payment request could not be paid at this time. Please try again later.",
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showRemoteSendConfirmation(confirm: @escaping VoidAction, tryAgain: @escaping VoidAction, cancel: @escaping VoidAction) -> UUID {
        banners.show(
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

//extension GiftCardAccount {
//    var url: URL {
//        URL.send(with: mnemonic)
//    }
//}

// MARK: - Mock -

extension Session {
    static let mock = Session(
        userID: .mock,
        organizer: .mock,
        client: .mock,
        flipClient: .mock,
        exchange: .mock,
        banners: .mock,
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
            .environmentObject(Banners.mock)
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
