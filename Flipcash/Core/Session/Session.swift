//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import Foundation
import FlipcashUI
import FlipcashCore

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published private(set) var balance: Fiat = 0
    
    @Published var billState: BillState = .default()
    @Published var presentationState: PresentationState = .hidden(.slide)
    
    @Published var valuation: BillValuation? = nil
    @Published var toast: Toast? = nil
    
    @Published var dialogItem: DialogItem?

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
    
    init(container: Container, historyController: HistoryController, ratesController: RatesController, owner: AccountCluster, userID: UserID) {
        self.container         = container
        self.client            = container.client
        self.ratesController   = ratesController
        self.historyController = historyController
        self.owner             = owner
        self.userID            = userID
        
        registerPoller()
        attemptAirdrop()
    }
    
    func prepareForLogout() {
        
    }
    
    // MARK: - Airdrop -
    
    private func attemptAirdrop() {
        // In rare cases account creation airdrop
        // might fail and so we'll have it again
        // in case the server has something to send
        Task {
            try await client.airdrop(type: .getFirstCrypto, owner: ownerKeyPair)
        }
    }
    
    // MARK: - Balance -
    
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
        try await fetchBalance()
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
    
    func withdraw(exchangedFiat: ExchangedFiat, to destination: PublicKey) async throws {
        let rendezvous = PublicKey.generate()!
        do {
            try await self.client.transfer(
                exchangedFiat: exchangedFiat,
                owner: owner,
                destination: destination,
                rendezvous: rendezvous,
                isWithdrawal: true
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
                
                updateBalance()
                historyController.sync()
                
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
            valuation = BillValuation(
                rendezvous: payload.rendezvous.publicKey,
                exchangedFiat: billDescription.exchangedFiat
            )
        }
        
        sendOperation     = operation
        presentationState = .visible(billDescription.received ? .pop : .slide)
        billState         = .init(
            bill: .cash(payload),
            primaryAction: .init(asset: .cancel, title: "Cancel") { [weak self] in
                self?.dismissCashBill(style: .slide)
            },
            secondaryAction: .init(asset: .airplane, title: "Send") { [weak self, weak operation] in
                if let operation {
                    self?.showCashLinkShareSheet(operation: operation, exchangedFiat: billDescription.exchangedFiat)
                }
            },
        )
        
        operation.start { [weak self] result in
            switch result {
            case .success:
                self?.enqueue(toast: .init(
                    amount: billDescription.exchangedFiat.converted,
                    isDeposit: false
                ))
                
                self?.updateBalance()
                self?.historyController.sync()
                
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
    
    private func showCashLinkShareSheet(operation: SendCashOperation, exchangedFiat: ExchangedFiat) {
        let payload = operation.payload
        
        let owner    = owner
        let giftCard = GiftCardCluster()
        let item     = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
        
        // Disable scanning of the bill
        // while the share sheet is up
        operation.ignoresStream = true
        
        ShareSheet.present(activityItem: item) { [weak self] didShare in
            guard let self = self else { return }
            
            if !didShare {
                operation.ignoresStream = false
            }
            
            guard didShare else {
                return
            }
            
            self.enqueue(toast: .init(
                amount: exchangedFiat.converted,
                isDeposit: false
            ))
            
            self.dismissCashBill(style: .pop)
            
            Task {
                do {
                    try await self.client.sendCashLink(
                        exchangedFiat: exchangedFiat,
                        ownerCluster: owner,
                        giftCard: giftCard,
                        rendezvous: payload.rendezvous.publicKey
                    )
                    
                    self.updateBalance()
                    self.historyController.sync()
                    
                } catch {
                    
                    ErrorReporting.captureError(error)
                    
                    Analytics.transfer(
                        event: .sendCashLink,
                        exchangedFiat: exchangedFiat,
                        successful: false,
                        error: error
                    )
                    
                    // TODO: Show error
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
    }
    
    // MARK: - Cash Links -
    
    func cancelCashLink(giftCardVault: PublicKey) async throws {
        try await client.voidCashLink(giftCardVault: giftCardVault, owner: ownerKeyPair)
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
                
                updateBalance()
                historyController.sync()
                
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
    
    private func showCashLinkNotAvailable() {
        dialogItem = .init(
            style: .destructive,
            title: "Cash Already Collected",
            subtitle: "This cash has already been collected",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
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
        owner: .init(authority: .derive(using: .primary(), mnemonic: .mock)),
        userID: UUID()
    )
}
