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
    
    var canPresentBill: Bool {
        billState.bill == nil
    }
    
    private let container: Container
    private let client: Client
    private let ratesController: RatesController
    private let historyController: HistoryController
    
    private var poller: Poller!
    
    private var scanOperation: ScanCashOperation?
    private var sendOperation: SendCashOperation?
    
    // MARK: - Init -
    
    init(container: Container, historyController: HistoryController, ratesController: RatesController, owner: AccountCluster, userID: UserID) {
        self.container         = container
        self.client            = container.client
        self.ratesController   = ratesController
        self.historyController = historyController
        self.owner             = owner
        self.userID            = userID
        
        registerPoller()
    }
    
    func prepareForLogout() {
        
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
    
    private func fetchBalance() async throws {
        balance = try await client.fetchAccountInfo(type: .primary, owner: ownerKeyPair).fiat
    }
    
    
    // MARK: - Toast -
    
    private func showToast(fiat: Fiat, isDeposit: Bool, autoDismiss: Bool = true) {
        toast = .init(
            amount: fiat,
            isDeposit: isDeposit
        )
        
        if autoDismiss {
            Task {
                try await Task.delay(seconds: 3)
                toast = nil
            }
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
            historyController: historyController,
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
                showCashBill(.init(
                    kind: .cash,
                    exchangedFiat: metadata.exchangedFiat,
                    received: true
                ))
                completion(.success)
                
            } catch ScanCashOperation.Error.noOpenStreamForRendezvous {
//                showCashExpiredError()
                completion(.noStream)
            } catch {
                completion(.failed)
            }
            
            // Update balance
        }
    }
    
    func showCashBill(_ billDescription: BillDescription) {
        let operation = SendCashOperation(
            client: client,
            owner: owner,
            exchangedFiat: billDescription.exchangedFiat
        )
        
        if billDescription.received {
            valuation = BillValuation(
                rendezvous: operation.payload.rendezvous.publicKey,
                exchangedFiat: billDescription.exchangedFiat
            )
        }
        
        sendOperation     = operation
        presentationState = .visible(billDescription.received ? .pop : .slide)
        billState         = .init(
            bill: .cash(operation.payload),
            primaryAction: .init(asset: .cancel, title: "Cancel") { [weak self] in
                self?.dismissCashBill(style: .slide)
            },
        )
        
        operation.start { [weak self] result in
            switch result {
            case .success(let success):
                self?.dismissCashBill(style: .pop)
                self?.showToast(
                    fiat: billDescription.exchangedFiat.converted,
                    isDeposit: false
                )
                
            case .failure(let failure):
                self?.dismissCashBill(style: .slide)
            }
        }
    }
    
    
    func dismissCashBill(style: PresentationState.Style) {
        if billState.shouldShowToast, let valuation = valuation {
            showToast(
                fiat: valuation.exchangedFiat.converted,
                isDeposit: true
            )
        }
        
        sendOperation = nil
        presentationState = .hidden(style)
        billState = .default()
        valuation = nil
    }
    
    // MARK: - Cash Links -
    
    func receiveCashLink(giftCard: GiftCardCluster) {
        Task {
            do {
                let giftCardAccountInfo = try await self.client.fetchAccountInfo(
                    type: .giftCard,
                    owner: giftCard.cluster.authority.keyPair
                )
                
                
                try await self.client.receiveCashLink(
                    fiat: giftCardAccountInfo.fiat,
                    ownerCluster: owner,
                    giftCard: giftCard
                )
                
                guard let exchangedFiat = giftCardAccountInfo.exchangedFiat else {
                    trace(.failure, components: "Gift card account info is missing ExchangeFiat.")
                    return
                }
                
                showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: exchangedFiat,
                        received: true
                    )
                )
                
                print("Gift card balance: \(giftCardAccountInfo)")
            } catch {
                trace(.failure, components: "Failed to receive cash link for gift card: \(giftCard)")
            }
        }
    }
    
    func showCashLinkBillWithShareSheet(exchangedFiat: ExchangedFiat) {
        let operation = SendCashOperation(
            client: client,
            owner: owner,
            exchangedFiat: exchangedFiat
        )
        
        let payload = operation.payload
        
        sendOperation     = operation
        presentationState = .visible(.slide)
        billState         = .init(
            bill: .cash(payload)
        )
        
        let owner    = owner
        let giftCard = GiftCardCluster()
        let item     = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
        
        ShareSheet.present(activityItem: item) { [weak self] isCompleted in
            guard let self = self else { return }
            
            self.dismissCashBill(style: .slide)
            if isCompleted {
                Task {
                    do {
                        try await self.client.sendCashLink(
                            exchangedFiat: exchangedFiat,
                            ownerCluster: owner,
                            giftCard: giftCard,
                            rendezvous: payload.rendezvous.publicKey
                        )
                        
                    } catch {
                        // TODO: Show error
                    }
                }
            }
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
