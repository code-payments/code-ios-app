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

protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published var showTipEntry: Bool = false
    
    @Published var isShowingPushPrompt: Bool = false
    
    @Published private(set) var isReceivingRemoteSend: Bool = false
    
    @Published private(set) var hasBalance: Bool = false
    @Published private(set) var currentBalance: Kin = 0
    @Published private(set) var billState: BillState = .default()
    @Published private(set) var presentationState: PresentationState = .hidden(.slide)
    
    @Published private(set) var phoneLink: PhoneLink?
    
    weak var delegate: SessionDelegate?
    
    let tipController: TipController
    
    let organizer: Organizer
    
    private(set) var user: User
    
    private let client: Client
    private let exchange: Exchange
    private let cameraSession: CameraSession<CodeExtractor>
    private let bannerController: BannerController
    private let reachability: Reachability
    private let betaFlags: BetaFlags
    private let abacus: Abacus
    private let historyController: HistoryController

    private let flowController: FlowController
    private let giftCardVault: GiftCardVault
    
    private var scannedRendezvous: Set<PublicKey> = []
    private var cancellables: Set<AnyCancellable> = []
    
    private var receiveTransaction: ReceiveTransaction?
    private var sendTransaction: SendTransaction?
    
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
    
    init(organizer: Organizer, user: User, client: Client, exchange: Exchange, cameraSession: CameraSession<CodeExtractor>, bannerController: BannerController, reachability: Reachability, betaFlags: BetaFlags, abacus: Abacus, historyController: HistoryController) {
        self.organizer = organizer
        self.user = user
        self.client = client
        self.exchange = exchange
        self.cameraSession = cameraSession
        self.bannerController = bannerController
        self.reachability = reachability
        self.betaFlags = betaFlags
        self.abacus = abacus
        self.historyController = historyController
        
        self.tipController = TipController(organizer: organizer, client: client, bannerController: bannerController)
        self.flowController = FlowController(client: client, organizer: organizer)
        self.giftCardVault = GiftCardVault()
        
        self.tipController.delegate = self
        
        registerCodeExtractorObserver()
        registerPoller()
        
        poll()
        
        historyController.fetchChats()
        
        Task {
            //try? await fetchAccountsForInstallation()
            try? await registerAppInstallation()
            
            try? await updatePhoneLinkStatus()
            try? await updateUserInfo()
            try? await updateUserPreferences()
            
            // Must be after user info
            try await receiveFirstKinIfAvailable()
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating Session")
    }
    
    func prepareForLogout() {
        tipController.prepareForLogout()
    }
    
    // MARK: - Setters -
    
    private func setIsReceivingRemoteSend(_ value: Bool) {
        isReceivingRemoteSend = value
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
    
    private func receiveFirstKinIfAvailable() async throws {
        if user.eligibleAirdrops.contains(.getFirstKin) {
            let metadata = try await airdropFirstKin()
            
            showToast(amount: metadata.amount, isDeposit: true)
            
            historyController.fetchChats()
        }
    }
    
    // MARK: - Installation -
    
    private func registerAppInstallation() async throws {
        let installation = try await AppContainer.installationID()
        
        try await client.registerInstallation(
            for: organizer.ownerKeyPair,
            installationID: installation
        )
    }
    
    private func fetchAccountsForInstallation() async throws -> [PublicKey] {
        try await client.fetchInstallationAccounts(for: try await AppContainer.installationID())
    }
    
    // MARK: - Camera Session -
    
    private func registerCodeExtractorObserver() {
        cameraSession.extraction.sink { [weak self] payload in
            if let payload = payload {
                self?.attempt(payload, request: nil)
            }
        }
        .store(in: &cancellables)
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
    
    // MARK: - Timelock Migration -
    
    private func migrateToPrivacyAccounts(legacyAccount: AccountInfo) async throws {
        Task {
            let amountToMigrate = legacyAccount.balance
            do {
                try await client.migrateToPrivacy(amountToMigrate: amountToMigrate, organizer: organizer)
                Analytics.migration(amount: amountToMigrate)
            } catch {
                ErrorReporting.captureMigration(error: error, tray: organizer.tray, amount: amountToMigrate)
                throw error
            }
            updateBalance()
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
                
            } catch ErrorFetchAccountInfos.migrationRequired(let accountInfo) {
                try await migrateToPrivacyAccounts(legacyAccount: accountInfo)
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
    
    func updatePhoneLinkStatus() async throws {
        phoneLink = try await client.fetchAssociatedPhoneNumber(owner: organizer.ownerKeyPair)
    }
    
    // MARK: - Timeout -
    
    private func timeoutStartTimer() {
        timeoutCancelTimer()
        
        let workItem = DispatchWorkItem(qos: .userInteractive, flags: []) { [weak self] in
            trace(.warning, components: "\(self?.timeoutInterval ?? 0) seconds reached. Putting away the bill away.")
            
            if let sendTransaction = self?.sendTransaction {
                Analytics.billTimeoutReached(kin: sendTransaction.payload.kin!, currency: sendTransaction.amount.rate.currency, animation: .slide) // It's always a slide
                
                // If a SendTransaction has been marked
                // inactive, we won't cancel it
                if !sendTransaction.isInactive {
                    self?.cancelSend()
                }
            }
        }
        
        timeoutCancelItem = workItem
        
        DispatchQueue.main.asyncAfter(
            deadline: .now() + timeoutInterval,
            execute: workItem
        )
    }
    
    func timeoutCancelTimer() {
        timeoutCancelItem?.cancel()
    }
    
    // MARK: - USDC Link -
    
    func linkUSDCAccount() async throws {
        try await client.linkAdditionalAccounts(
            owner: organizer.ownerKeyPair,
            linkedAccount: organizer.swapKeyPair
        )
        
        try await fetchBalance()
    }
    
    // MARK: - Remote Send -
    
    func sendRemotely() async throws {
        guard let sendTransaction = sendTransaction else {
            return
        }
        
        guard sendTransaction.amount.kin > 0 else {
            return
        }
        
        try await sendRemotely(sendTransaction: sendTransaction)
    }
    
    private func sendRemotely(sendTransaction: SendTransaction) async throws {
        // If there's an active SendTransaction, we'll mark
        // it inactive to prevent scannability and disable
        // the timeout for the bill to ensure it stays on-screen
        sendTransaction.markInactive()
        
        let giftCard = GiftCardAccount()
        let amount = sendTransaction.amount
        
        do {
            currentBalance = try await flowController.sendRemotely(
                amount: amount,
                rendezvous: sendTransaction.payload.rendezvous.publicKey,
                giftCard: giftCard
            )
            
            giftCardVault.insert(giftCard)
            
            presentShareSheet(for: giftCard, amount: amount)
            
            Analytics.remoteSendOutgoing(
                kin: amount.kin,
                currency: amount.rate.currency
            )
            
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to remote send.")
            throw error
        }
    }
    
    private func presentShareSheet(for giftCard: GiftCardAccount, amount: KinAmount) {
        let shareItem = ShareCashItem(
            giftCard: giftCard,
            amount: amount
        )
        
        UIApplication.shouldPauseInterfaceReset = true
        
        ShareSheet.present(activityItem: shareItem) { [unowned self] in
            trace(.warning, components: "Share dismissed")
            
            confirmationBannerID = showRemoteSendConfirmation { [unowned self] in
                resetConfirmationBanner()
                cancelSend(with: .pop)
                
            } tryAgain: { [unowned self] in
                resetConfirmationBanner()
                presentShareSheet(for: giftCard, amount: amount)
                
            } cancel: { [unowned self] in
                resetConfirmationBanner()
                cancelSend(with: .slide)
                Task {
                    try await cancelRemoteSend(giftCard: giftCard, amount: amount)
                }
            }
            
            Task { [weak self] in
                let bannerID = self?.confirmationBannerID
                try await Task.delay(seconds: 30) // 2.5 min
                
                // Check to see if the bannerID is the same
                // as the one that was assigned before the
                // delay, it might have been dismissed
                guard bannerID == self?.confirmationBannerID else {
                    return
                }
                
                // If the Session is no longer alive after the delay
                // the unowned reference to it from Task will crash unless
                // we weakly reference it explicitly.
                self?.dismissRemoteSendConfirmation()
            }
        }
        
        // Don't show the remote send and cancel buttons
        billState = billState.hideBillButtons(true)
    }
    
    private func resetConfirmationBanner() {
        confirmationBannerID = nil
        UIApplication.shouldPauseInterfaceReset = false
    }
    
    private func dismissRemoteSendConfirmation() {
        guard let bannerID = confirmationBannerID else {
            return
        }
        
        resetConfirmationBanner()
        
        bannerController.dismiss(id: bannerID)
        cancelSend(with: .pop)
    }
    
    func receiveRemoteSend(giftCard: GiftCardAccount) {
        dismissRemoteSendConfirmation()
        
        setIsReceivingRemoteSend(true)
        
        balanceQueue.enqueue { [unowned self] in
            Task {
                // Delay the presentation of the bill
                try await Task.delay(milliseconds: 500)
                
                defer {
                    setIsReceivingRemoteSend(false)
                }
                
                do {
                    let (receivedAmount, balance) = try await flowController.receiveRemote(giftCard: giftCard)
                    currentBalance = balance
                    
                    // Don't show the remote send and cancel buttons
                    billState = billState.hideBillButtons(true)
                    
                    initiateSend(
                        bill: Bill(
                            kind: .remote,
                            amount: receivedAmount,
                            didReceive: true
                        )
                    )
                    
                    giftCardVault.remove(giftCard)
                    
                    Analytics.remoteSendIncoming(
                        kin: receivedAmount.kin,
                        currency: receivedAmount.rate.currency,
                        isVoiding: false
                    )
                    
                    if let stopwatch = abacus.end(.cashLinkGrabTime) {
                        Analytics.cashLinkGrab(
                            kin: receivedAmount.kin,
                            currency: receivedAmount.rate.currency,
                            millisecondsToGrab: stopwatch.measure(in: .milliseconds)
                        )
                    }
                    
                } catch FlowController.Error.giftCardClaimed {
                    showGiftCardClaimedError()
                    
                } catch FlowController.Error.giftCardExpired {
                    showGiftCardExpiredError()
                    
                } catch {
                    showGiftCardCollectionFailedError()
                    ErrorReporting.captureError(error, reason: "Failed to receive remote send.")
                }
            }
        }
    }
    
    private func cancelRemoteSend(giftCard: GiftCardAccount, amount: KinAmount) async throws {
        do {
            currentBalance = try await flowController.cancelRemoteSend(
                giftCard: giftCard,
                amount: amount.kin
            )
            
            giftCardVault.remove(giftCard)
            
            Analytics.remoteSendIncoming(
                kin: amount.kin,
                currency: amount.rate.currency,
                isVoiding: true
            )
            
        } catch {
            ErrorReporting.captureError(error, reason: "Failed to refund remote send attempt.")
            throw error
        }
    }
    
    // MARK: - AirDrop -
    
    func airdropFirstKin() async throws -> PaymentMetadata {
        let (metadata, balance) = try await flowController.airdropFirstKin()
        currentBalance = balance
        
        Task {
            try await updateUserInfo()
        }
        
        Analytics.claimGetFreeKin(kin: metadata.amount.kin)
        
        return metadata
    }
    
    // MARK: - Receive -
    
    func attemptScanFromLibrary(image: UIImage) {
        Task.detached {
            do {
                let stopwatch = Stopwatch()
                var scanned = false
                if let payload = try CodeExtractor.extract(from: image) {
                    await self.attempt(payload, request: nil)
                    scanned = true
                } else {
                    await self.showNoCodeFoundError()
                }
                
                let milliseconds = stopwatch.measure(in: .milliseconds)
                trace(.warning, components: "Scanned in \(milliseconds) ms")
                Analytics.photoScanned(success: scanned, timeToScan: milliseconds)
                
            } catch {
                ErrorReporting.captureError(error)
                await self.showNoCodeFoundError()
            }
        }
    }
    
    func attempt(_ payload: Code.Payload, request: DeepLinkRequest?) {
        guard canPresentCard() else {
            trace(.warning, components: "Can't initiate send.")
            return
        }
        
        guard !scannedRendezvous.contains(payload.rendezvous.publicKey) else {
            trace(.warning, components: "Nonce previously received: \(payload.nonce.hexEncodedString())")
            return
        }
        
        if betaFlags.hasEnabled(.vibrateOnScan) {
            Feedback.tap()
        }
        
        trace(.note, components: scannedRendezvous.map { $0.base58 })
        
        receiveTransaction = nil
        scannedRendezvous.insert(payload.rendezvous.publicKey)
        
        guard reachability.status == .online else {
            showConnectivityError { [weak self] in
                self?.scannedRendezvous.remove(payload.rendezvous.publicKey)
            }
            return
        }
        
        trace(.note, components:
              "Kind: \(payload.kind)",
              "Nonce: \(payload.nonce.hexEncodedString())",
              "Rendezvous: \(payload.rendezvous.publicKey.base58)"
        )
        
        switch payload.kind {
        case .cash, .giftCard:
            ErrorReporting.breadcrumb(
                name: "[Bill] Scanned cash",
                type: .user
            )
            attemptReceive(payload)
            
        case .requestPayment, .requestPaymentV2:
            ErrorReporting.breadcrumb(
                name: "[Bill] Scanned request card",
                type: .user
            )
            attemptPayment(payload, request: request)
            
        case .login:
            ErrorReporting.breadcrumb(
                name: "[Bill] Scanned login card",
                type: .user
            )
            attemptLogin(payload, request: request)
            
        case .tip:
            ErrorReporting.breadcrumb(
                name: "[Bill] Scanned tip card",
                type: .user
            )
            attemptTip(payload)
        }
    }
    
    // MARK: - Tips -
    
    private func attemptTip(_ payload: Code.Payload) {
        guard case .username(let username) = payload.value else {
            return
        }
        
        presentScannedTipCard(
            payload: payload,
            username: username
        )
    }
    
    func presentMyTipCard(user: TwitterUser) {
        guard canPresentCard() else {
            return
        }
        
        tipController.setHasSeenTipCard()
        
        let payload = Code.Payload(
            kind: .tip,
            username: user.username
        )
        
        sendTransaction = nil
        presentationState = .visible(.slide)
        billState = billState
            .bill(
                .tip(.init(
                    username: user.username,
                    data: payload.codeData()
                ))
            )
            .hideBillButtons(false)
            .primaryAction(.init(
                asset: .send,
                title: Localized.Action.shareAsURL,
                action: { [weak self] in
                    self?.shareMyTipCard(user: user)
                }
            ))
            .secondaryAction(.init(
                asset: .cancel,
                title: nil,
                action: { [weak self] in
                    self?.cancelTip()
                }
            ))
        
        ErrorReporting.breadcrumb(
            name: "[Bill] Show my tip card",
            type: .user
        )
        
        promptForPushPermissionsIfNeeded()
        
        UIApplication.shouldPauseInterfaceReset = true
    }
    
    private func shareMyTipCard(user: TwitterUser) {
        ShareSheet.present(url: URL.tipCard(with: user.username))
    }
    
    private func promptForPushPermissionsIfNeeded() {
        Task {
            if await tipController.shouldPromptForPushPermissions() {
                try await Task.delay(milliseconds: 500)
                isShowingPushPrompt = true
                tipController.setPushPrompted()
            }
        }
    }
    
    func presentScannedTipCard(payload: Code.Payload, username: String) {
        sendTransaction = nil
        presentationState = .visible(.pop)
        billState = billState
            .bill(
                .tip(.init(
                    username: username,
                    data: payload.codeData()
                ))
            )
            .hideBillButtons(true)
        
        // Tip codes are always the same, we need to
        // ensure that we can scan the same code again
        scannedRendezvous.remove(payload.rendezvous.publicKey)
        
        // Ensure that we can cancel the presentation
        // of the amount entry modal in case the tip
        // card is invalid
        let showTask = Task {
            try await Task.delay(milliseconds: 750)
            
            if !Task.isCancelled {
                showTipEntry = true
                Analytics.tipCardShown(username: username)
            }
        }
        
        Task {
            do {
                try await tipController.fetchUser(username: username, payload: payload)
                
            } catch { // User not found
                
                showTask.cancel()
                
                showTipCardNotActivatedError(for: username)
            }
        }
    }
    
    func presentTipConfirmation(amount: KinAmount) {
        guard let (username, payload) = tipController.inflightUser else {
            return
        }
        
        let avatar = tipController.userAvatar
        let user   = tipController.userMetadata
        
        billState = billState
            .showTipConfirmation(
                .init(
                    payload: payload,
                    amount: amount,
                    username: username,
                    avatar: avatar,
                    user: user
                )
            )
        
        // If metadata isn't loaded yet,
        // we'll attempt to refetch it
        if user == nil {
            Task {
                try await tipController.fetchUser(username: username, payload: payload)
                presentTipConfirmation(amount: amount)
            }
        }
    }
    
    func completeTipPayment(amount: KinAmount) async throws {
        guard let metadata = tipController.userMetadata else {
            return
        }
        
        // Generally, we would use the rendezvous key that
        // was generated from the scan code payload, however,
        // tip codes are inherently deterministic and won't
        // change so we need a unique rendezvous for every tx.
        let rendezvous = PublicKey.generate()!
        
        do {
            try await flowController.transfer(
                amount: amount,
                fee: 0,
                additionalFees: [],
                rendezvous: rendezvous,
                destination: metadata.tipAddress,
                withdrawal: true,
                tipAccount: .x(metadata.username)
            )
            
            showToast(delayInMilliseconds: 1750, amount: amount, isDeposit: false)
            
            Analytics.transferForTip(
                amount: amount,
                successful: true,
                error: nil
            )
            
        } catch {
            Analytics.transferForTip(
                amount: amount,
                successful: false,
                error: error
            )
            
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: rendezvous,
                tray: organizer.tray,
                amount: amount
            )
            
            throw error
        }
    }
    
    func cancelTipAmountEntry() {
        // Cancelling from amount entry is triggered by a UI event.
        // To distinguish between a valid "Next" action that will
        // also dismiss the entry screen, we need to check explicitly
        if billState.tipConfirmation == nil {
            cancelTip()
        }
    }
    
    func cancelTip() {
        tipController.resetInflightUser()
        
        // The tip flow might be cancelled because of an invalid
        // tip card, in that case, we'll need to dismiss the
        // amount entry as well if it's open. That can happen if
        // the request to fetchUser takes longer than the delay
        // to open the entry screen.
        showTipEntry = false
        
        presentationState = .hidden(.slide)
        billState = billState
            .bill(nil)
            .showTipConfirmation(nil)
            .hideBillButtons(false)
            .primaryAction(nil)
            .secondaryAction(nil)
        
        UIApplication.shouldPauseInterfaceReset = false
    }
    
    // MARK: - Cash -
    
    private func attemptReceive(_ payload: Code.Payload) {
        let transaction = ReceiveTransaction(organizer: organizer, payload: payload, client: client)
        Task {
            do {
                let (metadata, millisecondsToScan) = try await transaction.start()
                initiateSend(
                    bill: Bill(
                        kind: .cash,
                        amount: metadata.amount,
                        didReceive: true
                    )
                )
                
                Analytics.grab(
                    kin: metadata.amount.kin,
                    currency: metadata.amount.rate.currency,
                    millisecondsToGrab: millisecondsToScan
                )
                
            } catch ReceiveTransaction.Error.noOpenStreamForRendezvous {
                // Do not remove the nonce from received pool
                showCashExpiredError()
            } catch {
                scannedRendezvous.remove(payload.rendezvous.publicKey)
            }
            
            updateBalance()
            receiveTransaction = nil
        }
        
        receiveTransaction = transaction
    }
    
    // MARK: - Login -
    
    private func attemptLogin(_ payload: Code.Payload, request: DeepLinkRequest?) {
        Task {
            // 1. Fetch message metadata for this payload to get the
            // domain for which we'll need to establish a relationship
            let messages = try await client.fetchMessages(rendezvous: payload.rendezvous)
            guard
                let message = messages.first,
                let loginAttempt = message.loginRequest
            else {
                trace(.failure, components: "Failed to receive login attempt. There were 0 messages for rendezvous: \(payload.rendezvous.publicKey.base58)")
                throw PaymentError.messageForRendezvousNotFound
            }
            
            presentLoginCard(
                payload: payload,
                domain: loginAttempt.domain,
                request: request
            )
        }
    }
    
    private func presentLoginCard(payload: Code.Payload, domain: Domain, request: DeepLinkRequest?) {
        Task {
            try await client.codeScanned(rendezvous: payload.rendezvous)
        }
        
        sendTransaction = nil
        presentationState = .visible(.pop)
        billState = billState
            .bill(
                .login(.init(
                    kinAmount: KinAmount(kin: 0, rate: .oneToOne),
                    data: payload.codeData(),
                    request: request
                ))
            )
            .showLoginConfirmation(.init(payload: payload, domain: domain))
            .hideBillButtons(true)

        Analytics.loginCardShown(domain: domain)
    }
    
    func completeLogin(for domain: Domain, rendezvous: PublicKey) async throws {
        let relationship: Relationship
        
        // 1. If the relationship already exists, we'll have
        // a local reference and we can skip the intent RPC
        if let r = organizer.relationship(for: domain) {
            trace(.success, components: "Skipping, relationship already exists")
            relationship = r
        } else {
            trace(.warning, components: "Relationship doesn't exist. Creating relationship to: \(domain.relationshipHost)")
            relationship = try await client.establishRelationship(organizer: organizer, domain: domain)
        }
        
        // 2. Perform the login using the relationship
        // private key to sign the request
        try await client.loginToThirdParty(
            rendezvous: rendezvous,
            relationship: relationship.cluster.authority.keyPair
        )
    }
    
    func rejectLogin() {
        guard let loginRendezvous = billState.loginConfirmation?.payload.rendezvous else {
            trace(.failure, components: "Failed to reject login, no rendezvous found in login confirmation.")
            return
        }
        
        cancelLogin(rejected: true)
        
        Task {
            try await client.rejectLogin(rendezvous: loginRendezvous)
        }
    }
    
    func cancelLogin(rejected: Bool) {
        if rejected {
            if let cancelURL = billState.bill?.metadata.request?.confirmParameters.cancelURL {
                cancelURL.openWithApplication()
            }
        } else {
            if let successURL = billState.bill?.metadata.request?.confirmParameters.successURL {
                successURL.openWithApplication()
            }
        }
        
        presentationState = .hidden(.slide)
        billState = billState
            .bill(nil)
            .showLoginConfirmation(nil)
            .hideBillButtons(false)
            .primaryAction(nil)
            .secondaryAction(nil)
    }
    
    // MARK: - Request -
    
    private func attemptPayment(_ payload: Code.Payload, request: DeepLinkRequest?) {
        guard case .fiat(let fiat) = payload.value else {
            return
        }
        
        guard let rate = exchange.rate(for: fiat.currency) else {
            return
        }
        
        trace(.warning, components: "Rate for \(rate.currency.rawValue.uppercased()): \(rate.fx)")
        
        let amount = KinAmount(
            fiat: fiat.amount,
            rate: rate
        )
        
        presentRequest(
            amount: amount,
            payload: payload,
            request: request
        )
        
        // Ensure that we preemptively pull funds into the
        // correct account before we attempt to pay a request
        receiveIfNeeded()
    }
    
    func presentRequest(amount: KinAmount, payload: Code.Payload?, request: DeepLinkRequest?) {
        let code: Code.Payload
        
        if let payload {
            code = payload
            
            Task {
                try await client.codeScanned(rendezvous: code.rendezvous)
            }
            
        } else {
            let fiat = Fiat(currency: amount.rate.currency, amount: amount.fiat)
            
            code = Code.Payload(
                kind: .requestPayment,
                fiat: fiat,
                nonce: .nonce
            )
            
            Task {
                try await client.sendRequestToReceiveBill(
                    destination: organizer.primaryVault,
                    fiat: fiat,
                    rendezvous: code.rendezvous
                )
            }
        }
        
        let isReceived = payload != nil
        
        presentationState = .visible(isReceived ? .pop : .slide)
        billState = billState
            .bill(
                .request(.init(
                    kinAmount: amount,
                    data: code.codeData(),
                    request: request
                ))
            )
            .secondaryAction(.init(
                asset: .cancel,
                title: Localized.Action.cancel,
                action: { [weak self] in
                    self?.cancelPayment(rejected: true, ignoreRedirect: true)
                }
            ))
        
        if isReceived {
            billState = billState
                .showPaymentConfirmation(
                    .init(
                        payload: code,
                        requestedAmount: amount,
                        localAmount: amount.replacing(rate: exchange.localRate)
                    )
                )
                .hideBillButtons(true)
        }
            
        Analytics.requestShown(amount: amount)
    }
    
    func cancelPayment(rejected: Bool, ignoreRedirect: Bool = false) {
        if let paymentRendezvous = billState.paymentConfirmation?.payload.rendezvous {
            scannedRendezvous.remove(paymentRendezvous.publicKey)
        }
        
        if let bill = billState.bill {
            let amount = bill.metadata.kinAmount
            
            Analytics.requestHidden(amount: amount)
            
            if rejected {
                if !ignoreRedirect, let cancelURL = bill.metadata.request?.confirmParameters.cancelURL {
                    cancelURL.openWithApplication()
                }
                
            } else {
                showToast(
                    amount: amount,
                    isDeposit: false
                )
                
                if !ignoreRedirect, let successURL = bill.metadata.request?.confirmParameters.successURL {
                    successURL.openWithApplication()
                }
            }
        }

        sendTransaction = nil
        presentationState = .hidden(.slide)
        billState = billState
            .bill(nil)
            .showPaymentConfirmation(nil)
            .hideBillButtons(false)
            .primaryAction(nil)
            .secondaryAction(nil)
    }
    
    func rejectPayment(ignoreRedirect: Bool = false) {
        guard let paymentRendezvous = billState.paymentConfirmation?.payload.rendezvous else {
            trace(.failure, components: "Failed to reject payment, no rendezvous found in payment confirmation.")
            return
        }
        
        cancelPayment(rejected: true, ignoreRedirect: ignoreRedirect)
        
        Task {
            try await client.rejectPayment(rendezvous: paymentRendezvous)
        }
    }
    
    func completePayment(for amount: KinAmount, rendezvous: KeyPair) async throws {
        
        var updatedAmount = amount
        
        do {
            try await exchange.fetchRatesIfNeeded()
            
            // 1. Ensure we have exchange rates and compute
            // the fees for this transaction
            
            guard let rateUSD = exchange.rate(for: .usd) else {
                throw PaymentError.noExchangeData
            }
            
            // The fee is a static $0.01 USD paid in Kin
            let fee = KinAmount(fiat: 0.01, rate: rateUSD)
            trace(.note, components: "Computed fee for transaction: \(fee.kin)")
            
            // 2. Between the time the kin value was computed previously and
            // now, the exchange rates might have changed. Let's recompute the
            // Kin value from the fiat value we had before but using a more
            // current exchange rate
            if let newRate = exchange.rate(for: amount.rate.currency) {
                updatedAmount = KinAmount(
                    fiat: amount.fiat,
                    rate: newRate
                )
                
                Analytics.recomputed(fxIn: amount.rate.fx, fxOut: newRate.fx)
                trace(.warning, components: "In:  \(amount.rate.fx)", "Out: \(newRate.fx)")
            }
            
            // 3. Fetch message metadata for this payload that
            // will tell us where to send the funds.
            
            let messages = try await client.fetchMessages(rendezvous: rendezvous)
            guard
                let message = messages.first,
                let receiveRequest = message.receiveRequest
            else {
                trace(.failure, components: "Failed to receive payments request. There were 0 messages for rendezvous: \(rendezvous.publicKey.base58)")
                throw PaymentError.messageForRendezvousNotFound
            }
            
            do {
                // 4. Establish a relationship if a domain is provided. If a verifier
                // is present that means the domain has been verified by the server.
                if let domain = receiveRequest.domain, receiveRequest.verifier != nil, organizer.relationship(for: domain) == nil {
                    try await client.establishRelationship(organizer: organizer, domain: domain)
                }
                
                // 5. Complete the transfer.
                try await flowController.transfer(
                    amount: updatedAmount,
                    fee: fee.kin,
                    additionalFees: receiveRequest.additionalFees,
                    rendezvous: rendezvous.publicKey,
                    destination: receiveRequest.account,
                    withdrawal: true
                )
                
                Analytics.transferForRequest(
                    amount: updatedAmount,
                    successful: true,
                    error: nil
                )
                
            } catch {
                Analytics.transferForRequest(
                    amount: updatedAmount,
                    successful: false,
                    error: error
                )
                
                throw error
            }
            
        } catch {
            Analytics.errorRequest(
                amount: updatedAmount,
                rendezvous: rendezvous.publicKey,
                error: error
            )
            
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: rendezvous.publicKey,
                tray: organizer.tray,
                amount: amount
            )
            
            showPaymentRequestError()
            
            throw error
        }
    }
    
    // MARK: - Send -
    
    private func canPresentCard() -> Bool {
        billState.bill == nil
    }
    
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
    
    func attemptSend(bill: Bill) {
        if canPresentCard() {
            initiateSend(bill: bill)
        } else {
            billQueue.append(bill)
        }
    }
    
    private func dequeueBillIfNeeded() {
        if !billQueue.isEmpty && canPresentCard() {
            initiateSend(
                bill: billQueue.removeFirst()
            )
        }
    }
    
    private func initiateSend(bill: Bill) {
        let transaction = SendTransaction(
            amount: bill.amount,
            organizer: organizer,
            client: client,
            flowController: flowController
        )
        
        if !bill.didReceive {
            ErrorReporting.breadcrumb(
                name: "[Bill] Pull out cash",
                amount: bill.amount,
                type: .user
            )
        }
        
        presentSend(transaction: transaction, bill: bill)
        
        transaction.startTransaction { [weak self] result in
            switch result {
            case .success:
                trace(.success, components: "Transaction successful")
                
                self?.cancelSend(with: .pop)
                
            case .failure(let error):
                switch error {
                case ErrorSubmitIntent.denied:
                    self?.showDeniedError()
                default:
                    break
                }
                
                trace(.failure, components: "Transaction failed: \(error)")
                self?.cancelSend(with: .slide)
            }
            
            self?.updateBalance()
            self?.flowController.updateLimits()
        }
    }
    
    private func presentSend(transaction: SendTransaction, bill: Bill) {
        timeoutStartTimer()
        
        if bill.didReceive {
            Task {
                try await Task.delay(milliseconds: 300)
                self.billState = self.billState.showValuation(
                    .init(
                        title: bill.title,
                        amount: bill.amount
                    )
                )
            }
        }
        
        let style: PresentationState.Style = bill.didReceive ? .pop : .slide
        
        sendTransaction = transaction
        presentationState = .visible(style)
        billState = billState
            .bill(
                .cash(.init(
                    kinAmount: bill.amount,
                    data: transaction.payloadData
                ))
            )
            .shouldShowToast(bill.didReceive)
            .primaryAction(.init(
                asset: .send,
                title: Localized.Action.send,
                action: { [weak self] in
                    try await self?.sendRemotely()
                },
                loadingStateDelayMillisenconds: 1000
            ))
            .secondaryAction(.init(
                asset: .cancel,
                title: Localized.Action.cancel,
                action: { [weak self] in
                    self?.cancelSend()
                }
            ))
        
        Analytics.billShown(kin: bill.amount.kin, currency: bill.amount.rate.currency, animation: style)
    }
    
    func cancelSend(with style: PresentationState.Style = .slide) {
        timeoutCancelTimer()
        
        if let sendTransaction = sendTransaction {
            Analytics.billHidden(kin: sendTransaction.payload.kin!, currency: sendTransaction.amount.rate.currency, animation: style)
        }
        
        showToastIfNeeded(style: style)
        
        presentationState = .hidden(style)
        sendTransaction = nil
        billState = billState
            .bill(nil)
            .shouldShowToast(false)
            .showToast(nil)
            .showValuation(nil)
            .hideBillButtons(false)
            .primaryAction(nil)
            .secondaryAction(nil)
        
        Task {
            try await Task.delay(milliseconds: 600)
            dequeueBillIfNeeded()
        }
    }
    
    private func showToastIfNeeded(style: PresentationState.Style) {
        guard let bill = billState.bill else {
            return
        }
        
        if style == .pop || billState.shouldShowToast {
            showToast(
                amount: bill.metadata.kinAmount,
                isDeposit: {
                    switch style {
                    case .slide: return true
                    case .pop:   return false
                    }
                }()
            )
        }
    }
    
    private func showToast(delayInMilliseconds: Int = 500, amount: KinAmount, isDeposit: Bool) {
        Task {
            try await Task.delay(milliseconds: delayInMilliseconds)
            self.billState = self.billState.showToast(
                .init(
                    amount: amount,
                    isDeposit: isDeposit
                )
            )
            
            try await Task.delay(seconds: 5)
            self.billState = self.billState.showToast(nil)
        }
    }
    
    // MARK: - State Changes -
    
    func willResignActive() {
        if let sendTransaction = sendTransaction, !sendTransaction.isInactive {
            cancelSend()
        }
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
    
    private func showTipCardNotActivatedError(for username: String) {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.tipCardNotActivated,
            description: Localized.Error.Description.tipCardNotActivated,
            actions: [
                .standard(title: Localized.Action.tweetThem) { [weak self] in
                    self?.tipController.openTwitterWithNudgeText(username: username)
                    Task {
                        try await Task.delay(seconds: 1)
                        self?.cancelTip()
                    }
                },
                .cancel(title: Localized.Action.ok) { [weak self] in
                    Task {
                        try await Task.delay(milliseconds: 400)
                        self?.cancelTip()
                    }
                },
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
        presentMyTipCard(user: user)
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
        cameraSession: SessionAuthenticator.mockCameraSession,
        bannerController: .mock,
        reachability: .mock,
        betaFlags: .mock,
        abacus: .mock,
        historyController: .mock
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
            .environmentObject(SessionAuthenticator.mockCameraSession)
            .environmentObject(CameraAuthorizer())
            .environmentObject(Client.mock)
            .environmentObject(BannerController.mock)
            .environmentObject(Exchange.mock)
            .environmentObject(ContentController.mock)
            .environmentObject(BetaFlags.shared)
            .environmentObject(NotificationController())
            .environmentObject(StatusController())
            .environmentObject(Reachability())
    }
}
