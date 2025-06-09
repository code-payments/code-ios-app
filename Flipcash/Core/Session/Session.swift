//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import UIKit
import FlipcashUI
import FlipcashCore

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published private(set) var balance: Fiat = 0
    @Published private(set) var limits: Limits?
    
    @Published var billState: BillState = .default()
    @Published var presentationState: PresentationState = .hidden(.slide)
    
    @Published var valuation: BillValuation? = nil
    @Published var toast: Toast? = nil
    
    @Published var dialogItem: DialogItem?

    let keyAccount: KeyAccount
    let owner: AccountCluster
    let userID: UserID
    
    var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
    var exchangedBalance: ExchangedFiat {
        try! ExchangedFiat(
            usdc: balance,
            rate: ratesController.rateForBalanceCurrency()
        )
    }
    
    var exchangedEntryBalance: ExchangedFiat {
        try! ExchangedFiat(
            usdc: balance,
            rate: ratesController.rateForEntryCurrency()
        )
    }
    
    var nextTransactionLimit: Fiat? {
        guard let limits else {
            return nil
        }
        
        let rate = ratesController.rateForEntryCurrency()
        
        guard let limit = limits.sendLimitFor(currency: rate.currency) else {
            return nil
        }
        
        return limit.nextTransaction
    }
    
    var isShowingBill: Bool {
        billState.bill != nil
    }
    
    private let container: Container
    private let client: Client
    private let ratesController: RatesController
    private let historyController: HistoryController
    
    private var poller: Poller!
    
    private var scanOperation: ScanCashOperation?
    private var sendOperation: SendCashOperation?
    
    private var toastQueue = ToastQueue()
    
    // MARK: - Init -
    
    init(container: Container, historyController: HistoryController, ratesController: RatesController, keyAccount: KeyAccount, owner: AccountCluster, userID: UserID) {
        self.container         = container
        self.client            = container.client
        self.ratesController   = ratesController
        self.historyController = historyController
        self.keyAccount        = keyAccount
        self.owner             = owner
        self.userID            = userID
        
        registerPoller()
        attemptAirdrop()
    }
    
    func prepareForLogout() {
        
    }
    
    // MARK: - Login -
    
    func attemptLogin(with mnemonic: MnemonicPhrase, completion: @escaping () async throws -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: "Log In?",
            subtitle: "You're already logged into an account. Please ensure you have saved your Access Key before proceeding. Would you like to logout and login with a new account?",
            dismissable: true,
            actions: {
                .destructive("Log Out & Log In") {
                    Task {
                        try await completion()
                    }
                };
                
                .cancel()
            }
        )
    }
    
    // MARK: - Lifecycle -
    
    func didEnterBackground() {
        // If the sendOperation is ignoring stream, it's likely
        // presenting a share sheet or in some way mid-process
        // so we don't want to dismiss the bill from under it
        if let sendOperation, !sendOperation.ignoresStream {
            dismissCashBill(style: .slide)
        }
    }
    
    // MARK: - Airdrop -
    
    private func attemptAirdrop() {
        Task {
            let paymentMetadata = try await client.airdrop(type: .welcomeBonus, owner: ownerKeyPair)
            
            try await Task.delay(milliseconds: 750)
            let exchangedFiat = paymentMetadata.exchangedFiat
            
            enqueue(toast: .init(
                amount: exchangedFiat.converted,
                isDeposit: true
            ))
            
            showCashBill(.init(
                kind: .cash,
                exchangedFiat: exchangedFiat,
                received: true
            ))
            
            // Don't show actions for this bill
            billState.primaryAction   = nil
            billState.secondaryAction = nil
        }
    }
    
    // MARK: - Balance -
    
    func hasLimitToSendFunds(for exchangedFiat: ExchangedFiat) -> Bool {
        guard let nextTransactionLimit else {
            return false
        }
        
        guard exchangedFiat.converted.currencyCode == nextTransactionLimit.currencyCode else {
            return false
        }
        
        return exchangedFiat.converted.quarks <= nextTransactionLimit.quarks
    }
    
    func hasSufficientFunds(for exchangedFiat: ExchangedFiat) -> Bool {
        exchangedFiat.usdc.quarks > 0 && exchangedFiat.usdc.quarks <= balance.quarks
    }
    
    // MARK: - Poller -
    
    private func registerPoller() {
        poller = Poller(seconds: 10, fireImmediately: true) { [weak self] in
            Task {
                try await self?.poll()
            }
        }
    }
    
    private func poll() async throws {
        try await fetchLimitsIfNeeded()
        try await fetchBalance()
    }
    
    // MARK: - Limits -
    
    private func fetchLimitsIfNeeded() async throws {
        if limits == nil || limits?.isStale == true {
            try await fetchLimits()
        }
    }
    
    private func fetchLimits() async throws {
        limits = try await client.fetchTransactionLimits(
            owner: ownerKeyPair,
            since: .todayAtMidnight()
        )
        
        trace(.note, components: "Daily limit updated (USD): \(limits?.sendLimitFor(currency: .usd)?.maxPerDay.decimalValue ?? -1)")
    }
    
    private func updateLimits() {
        Task {
            try await fetchLimits()
        }
    }
    
    // MARK: - Balance -
    
    func fetchBalance() async throws {
        balance = try await client.fetchAccountInfo(type: .primary, owner: ownerKeyPair).fiat
    }
    
    func updateBalance() {
        Task {
            try await fetchBalance()
        }
    }
    
    func updatePostTransaction() {
        updateBalance()
        updateLimits()
        historyController.sync()
    }
    
    // MARK: - Toast -
    
    private func show(toast: Toast) {
        enqueue(toast: toast)
        if self.toast == nil {
            consumeToast()
        }
    }
    
    private func enqueue(toast: Toast) {
        toastQueue.insert(toast)
    }
    
    private func consumeToast() {
        guard toastQueue.hasToasts else {
            return
        }
        
        Task {
            // Wait for bill animation to finish
            // before showing the toast
            try await Task.delay(milliseconds: 500)
            
            // Ensure that there's no bills showing
            // otherwise we'll wait for dismissBill
            // to consume the toast
            guard !isShowingBill else {
                trace(.note, components: "Bill showing, waiting for toasts to resume...")
                return
            }
            
            guard toastQueue.hasToasts else {
                return
            }
            
            toast = toastQueue.pop()
//            trace(.note, components: "Showing toast: \(toast!.amount.formatted(suffix: nil))")
            
            try await Task.delay(seconds: 3)
            toast = nil
            
            if toastQueue.hasToasts {
                try await Task.delay(milliseconds: 1000)
                consumeToast()
            }
        }
    }
    
    // MARK: - Withdrawals -
    
    func withdraw(exchangedFiat: ExchangedFiat, to destinationMetadata: DestinationMetadata) async throws {
        let rendezvous = PublicKey.generate()!
        do {
            try await self.client.withdraw(
                exchangedFiat: exchangedFiat,
                owner: owner,
                destinationMetadata: destinationMetadata,
            )
            
            historyController.sync()
            
            Analytics.withdrawal(
                exchangedFiat: exchangedFiat,
                successful: true,
                error: nil
            )
            
        } catch {
            
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: rendezvous,
                exchangedFiat: exchangedFiat
            )
            
            Analytics.withdrawal(
                exchangedFiat: exchangedFiat,
                successful: false,
                error: error
            )
            
            throw error
        }
    }
    
    // MARK: - Cash -
    
    func receiveCash(_ payload: CashCode.Payload, completion: @escaping (ReceiveCashResult) -> Void) {
        print("Scanned: \(payload.fiat.formatted(suffix: nil)) \(payload.fiat.currencyCode)")
        
        guard scanOperation == nil else {
            return
        }
        
        let operation = ScanCashOperation(
            client: client,
            owner: owner,
            payload: payload
        )
        
        scanOperation = operation
        Task {
            defer {
                scanOperation = nil
            }
            
            do {
                let metadata = try await operation.start()
                
                updatePostTransaction()
                
                enqueue(toast: .init(
                    amount: metadata.exchangedFiat.converted,
                    isDeposit: true
                ))
                
                showCashBill(.init(
                    kind: .cash,
                    exchangedFiat: metadata.exchangedFiat,
                    received: true
                ))
                
                Analytics.transfer(
                    event: .grabBill,
                    exchangedFiat: metadata.exchangedFiat,
                    successful: true,
                    error: nil
                )
                completion(.success)
                
            } catch ScanCashOperation.Error.noOpenStreamForRendezvous {
//                showCashExpiredError()
                completion(.noStream)
                
            } catch {
                ErrorReporting.capturePayment(
                    error: error,
                    rendezvous: payload.rendezvous.publicKey,
                    fiat: payload.fiat
                )
                
                Analytics.transfer(
                    event: .grabBill,
                    fiat: payload.fiat,
                    successful: false,
                    error: error
                )
                completion(.failed)
            }
        }
    }
    
    func showCashBill(_ billDescription: BillDescription) {
        let operation = SendCashOperation(
            client: client,
            owner: owner,
            exchangedFiat: billDescription.exchangedFiat
        )
        
        let payload = operation.payload
        
        if billDescription.received {
            Task {
                try await Task.delay(milliseconds: 300)
                valuation = BillValuation(
                    rendezvous: payload.rendezvous.publicKey,
                    exchangedFiat: billDescription.exchangedFiat
                )
            }
        }
        
        sendOperation     = operation
        presentationState = .visible(billDescription.received ? .pop : .slide)
        billState         = .init(
            bill: .cash(payload),
            primaryAction: .init(asset: .airplane, title: "Send") { [weak self, weak operation] in
                if let operation, let self {
                    // Disable scanning of the bill
                    // while the share sheet is up
                    operation.ignoresStream = true
                    
                    let payload       = operation.payload
                    let exchangedFiat = billDescription.exchangedFiat
                    
                    do {
                        let giftCard = try await self.createCashLink(
                            payload: payload,
                            exchangedFiat: exchangedFiat
                        )
                        
                        self.showCashLinkShareSheet(
                            giftCard: giftCard,
                            exchangedFiat: exchangedFiat
                        )
                        
                    } catch {
                        ErrorReporting.captureError(error)
                        showSomethingWentWrongError()
                    }
                }
            },
            secondaryAction: .init(asset: .cancel, title: "Cancel") { [weak self] in
                self?.dismissCashBill(style: .slide)
            },
        )
        
        operation.start { [weak self] result in
            switch result {
            case .success:
                self?.enqueue(toast: .init(
                    amount: billDescription.exchangedFiat.converted,
                    isDeposit: false
                ))
                
                self?.updatePostTransaction()
                
                self?.dismissCashBill(style: .pop)
                
                Analytics.transfer(
                    event: .giveBill,
                    exchangedFiat: billDescription.exchangedFiat,
                    successful: true,
                    error: nil
                )
                
            case .failure(let error):
                self?.dismissCashBill(style: .slide)
                
                ErrorReporting.capturePayment(
                    error: error,
                    rendezvous: payload.rendezvous.publicKey,
                    exchangedFiat: billDescription.exchangedFiat
                )
                
                Analytics.transfer(
                    event: .giveBill,
                    exchangedFiat: billDescription.exchangedFiat,
                    successful: false,
                    error: error
                )
            }
        }
    }
    
    private func showCashLinkShareSheet(giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat) {
        UIApplication.isInterfaceResetDisabled = true
        
        let item = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
        ShareSheet.present(activityItem: item) { [weak self] didShare in
            guard let self = self else { return }
            
            let hideBillActions = {
                self.billState.primaryAction = nil
                self.billState.secondaryAction = nil
            }
            
            let cancelSend = {
                self.dismissCashBill(style: .slide)
                Task {
                    do {
                        try await self.cancelCashLink(giftCardVault: giftCard.cluster.vaultPublicKey)
                        self.updatePostTransaction()
                    } catch {
                        ErrorReporting.captureError(error)
                    }
                }
            }
            
            let completeSend = {
                _ = Task {
                    try await Task.delay(milliseconds: 250)
                    
                    self.enqueue(toast: .init(
                        amount: exchangedFiat.converted,
                        isDeposit: false
                    ))
                    
                    self.dismissCashBill(style: .pop)
                    self.updatePostTransaction()
                }
            }
            
            self.dialogItem = .init(
                style: .success,
                title: "Did you send the link?",
                subtitle: "Any cash that isn't collected within 24 hours will be automatically returned to your balance",
                dismissable: false,
            ) {
                .standard("Yes") {
                    hideBillActions()
                    completeSend()
                };
                
                .subtle("No, Cancel Send") {
                    hideBillActions()
                    cancelSend()
                }
            }
        }
    }
    
    func dismissCashBill(style: PresentationState.Style) {
        consumeToast()
        
        sendOperation = nil
        presentationState = .hidden(style)
        billState = .default()
        valuation = nil
        
        UIApplication.isInterfaceResetDisabled = false
    }
    
    // MARK: - Cash Links -
    
    private func createCashLink(payload: CashCode.Payload, exchangedFiat: ExchangedFiat) async throws -> GiftCardCluster {
        do {
            let giftCard = GiftCardCluster()
            try await client.sendCashLink(
                exchangedFiat: exchangedFiat,
                ownerCluster: owner,
                giftCard: giftCard,
                rendezvous: payload.rendezvous.publicKey
            )
            
            Analytics.transfer(
                event: .sendCashLink,
                exchangedFiat: exchangedFiat,
                successful: true,
                error: nil
            )
            
            return giftCard
            
        } catch {
            ErrorReporting.captureError(error)
            
            Analytics.transfer(
                event: .sendCashLink,
                exchangedFiat: exchangedFiat,
                successful: false,
                error: error
            )
            
            // TODO: Show error
            
            throw error
        }
    }
    
    func cancelCashLink(giftCardVault: PublicKey) async throws {
        try await client.voidCashLink(giftCardVault: giftCardVault, owner: ownerKeyPair)
        
        updatePostTransaction()
    }
    
    func receiveCashLink(giftCard: GiftCardCluster) {
        Task {
            do {
                let giftCardAccountInfo = try await client.fetchAccountInfo(
                    type: .giftCard,
                    owner: giftCard.cluster.authority.keyPair
                )
                
                guard let exchangedFiat = giftCardAccountInfo.exchangedFiat else {
                    trace(.failure, components: "Gift card account info is missing ExchangeFiat.")
                    return
                }
                
                guard giftCardAccountInfo.claimState != .claimed && giftCardAccountInfo.claimState != .expired else {
                    showCashLinkNotAvailable()
                    return
                }
                
                try await client.receiveCashLink(
                    usdc: exchangedFiat.usdc,
                    ownerCluster: owner,
                    giftCard: giftCard
                )
                
                updatePostTransaction()
                
                enqueue(toast: .init(
                    amount: exchangedFiat.converted,
                    isDeposit: true
                ))
                
                showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: exchangedFiat,
                        received: true
                    )
                )
                
                // Don't show actions for cash links
                billState.primaryAction   = nil
                billState.secondaryAction = nil
                
                Analytics.transfer(
                    event: .receiveCashLink,
                    exchangedFiat: exchangedFiat,
                    successful: true,
                    error: nil
                )
                
            } catch {
                ErrorReporting.captureError(error)
                
                Analytics.transfer(
                    event: .receiveCashLink,
                    exchangedFiat: nil,
                    successful: false,
                    error: error
                )
                
                showCashLinkNotAvailable()
                trace(.failure, components: "Failed to receive cash link for gift card: \(giftCard)")
            }
        }
    }
    
//    func showCashLinkBillWithShareSheet(exchangedFiat: ExchangedFiat) {
//        let operation = SendCashOperation(
//            client: client,
//            owner: owner,
//            exchangedFiat: exchangedFiat
//        )
//        
//        let payload = operation.payload
//        
//        let owner    = owner
//        let giftCard = GiftCardCluster()
//        let item     = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
//        
//        ShareSheet.present(activityItem: item) { [weak self] didShare in
//            guard let self = self else { return }
//            
//            if didShare {
//                self.enqueue(toast: .init(
//                    amount: exchangedFiat.converted,
//                    isDeposit: false
//                ))
//            }
//            
//            self.dismissCashBill(style: didShare ? .pop : .slide)
//            
//            if didShare {
//                Task {
//                    do {
//                        try await self.client.sendCashLink(
//                            exchangedFiat: exchangedFiat,
//                            ownerCluster: owner,
//                            giftCard: giftCard,
//                            rendezvous: payload.rendezvous.publicKey
//                        )
//                        
//                        self.updateBalance()
//                        
//                    } catch {
//                        
//                        ErrorReporting.captureError(error)
//                        
//                        Analytics.transfer(
//                            event: .sendCashLink,
//                            exchangedFiat: exchangedFiat,
//                            successful: false,
//                            error: error
//                        )
//                        
//                        // TODO: Show error
//                    }
//                }
//            }
//        }
//        
//        Task {
//            try await Task.delay(milliseconds: 350)
//            
//            sendOperation     = operation
//            presentationState = .visible(.slide)
//            billState         = .init(
//                bill: .cash(payload)
//            )
//        }
//    }
    
    // MARK: - Errors -
    
    private func showSomethingWentWrongError() {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showCashLinkNotAvailable() {
        dialogItem = .init(
            style: .destructive,
            title: "Cash Already Collected",
            subtitle: "This cash has already been collected, or was cancelled by the sender",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

// MARK: - Errors -

extension Session {
    enum Error: Swift.Error {
        case cashLinkCreationFailed
    }
}

// MARK: - ReceiveCashResult -

extension Session {
    enum ReceiveCashResult {
        case success
        case noStream
        case failed
    }
}

// MARK: - BillDescription -

extension Session {
    struct BillDescription {
        enum Kind {
            case cash
        }
        
        let kind: Kind
        let exchangedFiat: ExchangedFiat
        let received: Bool
        
        init(kind: Kind, exchangedFiat: ExchangedFiat, received: Bool) {
            self.kind = kind
            self.exchangedFiat = exchangedFiat
            self.received = received
        }
    }
}

// MARK: - Mock -

extension Session {
    static let mock = Session(
        container: .mock,
        historyController: .mock,
        ratesController: .mock,
        keyAccount: .mock,
        owner: .init(authority: .derive(using: .primary(), mnemonic: .mock)),
        userID: UUID()
    )
}
