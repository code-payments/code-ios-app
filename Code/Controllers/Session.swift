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
    
    @Published private(set) var isReceivingRemoteSend: Bool = false
    
    @Published private(set) var hasBalance: Bool = false
    @Published private(set) var currentBalance: Kin = 0
    @Published private(set) var billState: BillState = .default()
    @Published private(set) var presentationState: PresentationState = .hidden(.slide)
    
    @Published private(set) var phoneLink: PhoneLink?
    
    weak var delegate: SessionDelegate?
    
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
        
        self.flowController = FlowController(client: client, organizer: organizer)
        self.giftCardVault = GiftCardVault()
        
        registerCodeExtractorObserver()
        registerPoller()
        
        poll()
        
        historyController.fetchAll()
        historyController.fetchChats()
        
        Task {
            try await updatePhoneLinkStatus()
            try await updateUserInfo()
            try await receiveFirstKinIfAvailable() // Must be after user info
            try await resetAppBadgeCount()
        }
    }
    
    deinit {
        trace(.warning, components: "Deallocating Session")
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
    
    private func receiveFirstKinIfAvailable() async throws {
        if user.eligibleAirdrops.contains(.getFirstKin) {
            let metadata = try await airdropFirstKin()
            
            showToast(amount: metadata.amount, isDeposit: true)
            
            historyController.fetchChats()
        }
    }
    
    private func resetAppBadgeCount() async throws {
        try await client.resetBadgeCount(for: organizer.ownerKeyPair)
        UIApplication.shared.applicationIconBadgeNumber = 0
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
//        fetchReferralAirdrops()
    }
    
    // MARK: - Referral Airdrops -
    
//    private func fetchReferralAirdrops() {
//        Task {
//            let owner = organizer.ownerKeyPair
//            let messages = try await client.fetchMessages(rendezvous: owner)
//            let referralAidrops = messages.filter { $0.airdrop != nil }
//            
//            // Queue up all referral airdrops as bills
//            // and show the first if there's no other
//            // bills being shown already
//            
//            if !referralAidrops.isEmpty {
//                billQueue.append(
//                    contentsOf: referralAidrops.map {
//                        Bill(
//                            kind: .referral,
//                            amount: $0.airdrop!.kinAmount,
//                            didReceive: true
//                        )
//                    }
//                )
//                
//                dequeueBillIfNeeded()
//            }
//            
//            if !messages.isEmpty {
//                try await client.acknowledge(
//                    messages: messages,
//                    rendezvous: owner.publicKey
//                )
//            }
//        }
//    }
    
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
                
                if organizer.isUnlocked {
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
    
    // MARK: - Remote Send -
    
    func sendRemotely(completion: @escaping VoidAction) {
        guard let sendTransaction = sendTransaction else {
            return
        }
        
        guard sendTransaction.amount.kin > 0 else {
            return
        }
        
        sendRemotely(sendTransaction: sendTransaction, completion: completion)
    }
    
    private func sendRemotely(sendTransaction: SendTransaction, completion: @escaping VoidAction) {
        // If there's an active SendTransaction, we'll mark
        // it inactive to prevent scannability and disable
        // the timeout for the bill to ensure it stays on-screen
        sendTransaction.markInactive()
        
        Task {
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
                completion()
                
                Analytics.remoteSendOutgoing(
                    kin: amount.kin,
                    currency: amount.rate.currency
                )
                
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to remote send.")
                throw error
            }
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
                    // TODO: Show error here
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
    
    func attempt(_ payload: Code.Payload, request: DeepLinkPaymentRequest?) {
        guard canInitiateSend() else {
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
            attemptReceive(payload)
            
        case .requestPayment:
            attemptPayment(payload, request: request)
        }
    }
    
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
    
    // MARK: - Request -
    
    private func attemptPayment(_ payload: Code.Payload, request: DeepLinkPaymentRequest?) {
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
    }
    
    func presentRequest(amount: KinAmount, payload: Code.Payload?, request: DeepLinkPaymentRequest?) {
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
                if !ignoreRedirect, let cancelURL = bill.metadata.request?.cancelURL {
                    UIApplication.shared.open(cancelURL)
                }
                
            } else {
                showToast(
                    amount: amount,
                    isDeposit: false
                )
                
                if !ignoreRedirect, let successURL = bill.metadata.request?.successURL {
                    UIApplication.shared.open(successURL)
                }
            }
        }

        sendTransaction = nil
        presentationState = .hidden(.slide)
        billState = billState
            .bill(nil)
            .showPaymentConfirmation(nil)
            .hideBillButtons(false)
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
                // 4. Establish a relationship if a domain is provided and is verified
                if let domain = receiveRequest.domain, organizer.relationship(for: domain) == nil {
                    // If a verifier is present, the domain
                    // is considered verified
                    if receiveRequest.verifier != nil {
                        try await client.establishRelationship(organizer: organizer, domain: domain)
                    }
                }
                
                // 5. Complete the transfer.
                try await flowController.transfer(
                    amount: updatedAmount,
                    fee: fee.kin,
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
            showPaymentRequestError()
            throw error
        }
    }
    
    // MARK: - Send -
    
    private func canInitiateSend() -> Bool {
        billState.bill == nil
    }
    
    func hasSufficientFunds(for amount: KinAmount) -> Bool {
        currentBalance >= amount.kin
    }
    
    func hasAvailableDailyLimit() -> Bool {
        todaysAllowanceFor(currency: .usd) > 0
    }
    
    func hasAvailableTransactionLimit(for amount: KinAmount) -> Bool {
        (flowController.limits?.todaysAllowanceFor(currency: amount.rate.currency) ?? 0) > amount.fiat
    }
    
    func todaysAllowanceFor(currency: CurrencyCode) -> Decimal {
        flowController.limits?.todaysAllowanceFor(currency: currency) ?? 0
    }
    
    func attemptSend(bill: Bill) {
        if canInitiateSend() {
            initiateSend(bill: bill)
        } else {
            billQueue.append(bill)
        }
    }
    
    private func dequeueBillIfNeeded() {
        if !billQueue.isEmpty && canInitiateSend() {
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
    
    private func showToast(amount: KinAmount, isDeposit: Bool) {
        Task {
            try await Task.delay(milliseconds: 500)
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

// MARK: - Errors -

extension Session {
    enum PaymentError: Swift.Error {
        case noExchangeData
        case invalidPayloadForRequest
        case exchangeForCurrencyNotFound
        case messageForRendezvousNotFound
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
