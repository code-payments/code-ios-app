//
//  StoreController.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import FlipcashCore
import StoreKit

@MainActor
protocol StoreControllerDelegate: AnyObject {
    func storeController(_ controller: StoreController, didReceivePurchaseResult result: StoreController.PurchaseResult)
}

@MainActor
class StoreController: NSObject, ObservableObject {
    
    weak var delegate: StoreControllerDelegate?
    
    @Published private(set) var products: [String: Product] = [:]
    
    private(set) var pendingPurchaseResults: [PurchaseResult] = []
    
    private var updates: Task<Void, Never>?
    
    // MARK: - Init -
    
    override init() {
        super.init()
        
        loadProductsIfNeeded()
        listenForTransactionUpdates()
    }
    
    private func listenForTransactionUpdates() {
        updates = Task { @MainActor [weak self] in
            print("[IAP] Listening for transaction updates...")
            for await update in Transaction.updates {
                guard let transaction = try? update.payloadValue else {
                    continue
                }
                
                guard let self = self else {
                    continue
                }
                
                print("[IAP] Async transaction received: \(transaction.id)")
                
                do {
                    let purchase = try await self.getPurchase(for: transaction)
                    
                    let finish: FinishTransaction = {
                        await transaction.finish()
                    }
                    
                    let result = PurchaseResult.success(purchase, finish)
                    
                    if let delegate = self.delegate {
                        print("[IAP] Notifying delegate of purchase result for: \(purchase.productID)")
                        delegate.storeController(self, didReceivePurchaseResult: result)
                    } else {
                        print("[IAP] No delegate assigned. Storing purchase result for: \(purchase.productID)")
                        pendingPurchaseResults.append(result)
                    }
                    
                } catch {
                    print("[IAP] Failed to get purchase: \(error)")
                    ErrorReporting.captureError(error)
                }
            }
        }
    }
    
    deinit {
        updates?.cancel()
        print("Deallocating StoreController.")
    }
    
    func loadProducts() async throws {
        do {
            let products = try await Product.products(for: IAPProduct.productIDs)
            self.products = products.elementsKeyed(by: \.id)
            print("[IAP] Loaded products:")
            products.forEach {
                print("\($0.id): \($0.displayPrice) - \($0.displayName)")
            }
        } catch {
            ErrorReporting.captureError(error)
            throw error
        }
    }
    
    func loadProductsIfNeeded() {
        guard products.isEmpty else {
            return
        }
        
        Task {
            try await loadProducts()
        }
    }
    
    // MARK: - Receipt -
    
    private func getReceipt() async throws -> Data {
        let f = FileManager.default
        
        if let receiptURL = Bundle.main.appStoreReceiptURL, f.fileExists(atPath: receiptURL.path) {
            print("[IAP] Found receipt. Loading...")
            do {
                return try Data(contentsOf: receiptURL)
            } catch {
                throw error
            }
        } else {
            print("[IAP] Receipt not found. Sending refresh request...")
            try await refreshReceipt()
            return try await getReceipt()
        }
    }
    
    func refreshReceipt() async throws {
        let delegate = ReceiptDelegate()
        
        return try await withCheckedThrowingContinuation { c in
            delegate.completion = {
                c.resume(with: $0)
            }
            
            let request = SKReceiptRefreshRequest()
            request.delegate = delegate
            request.start()
        }
    }
    
    // MARK: - Actions -

    func pay(for iap: IAPProduct, owner: KeyPair, uniqueID: UUID) async throws -> PurchaseResult {
        if products.isEmpty {
            print("[IAP] Loading products before purchase.")
            try await loadProducts()
        }
        
        guard let product = products[iap.rawValue] else {
            print("[IAP] Can't make purchases.")
            throw Error.productNotFound
        }
        
        guard await Transaction.latest(for: iap.rawValue) == nil else {
            print("[IAP] Product already purchased: \(iap.rawValue)")
            throw Error.productAlreadyPurchased
        }
        
        let result = try await product.purchase(
            options: [
                .appAccountToken(uniqueID),
            ]
        )
        
        switch result {
        case .success(let purchaseResult):
            
            switch purchaseResult {
            case .unverified(_, let error):
                print("[IAP] Purchase could not be verified: \(error)")
                let transaction = try purchaseResult.payloadValue
                await transaction.finish()
                return .failed
                
            case .verified(let transaction):
                print("[IAP] Purchase success. Tx: \(transaction.id)")
                let purchase = try await getPurchase(for: transaction)
                
                let finish: FinishTransaction = {
                    await transaction.finish()
                }
                
                return .success(purchase, finish)
            }
            
        case .userCancelled:
            print("[IAP] Purchase cancelled")
            return .cancelled
            
        case .pending:
            return .pending
            
        @unknown default:
            print("[IAP] Unknown purchase result: \(result)")
            return .failed
        }
    }
    
    private func getPurchase(for transaction: Transaction) async throws -> Purchase {
        try await refreshReceipt()
        
        let receipt = try await getReceipt()
        print("[IAP] Receipt: \(receipt.base64EncodedString())")
        
        return Purchase(
            uniqueID: transaction.appAccountToken ?? UUID(),
            productID: transaction.productID,
            price: transaction.price,
            currencyCode: transaction.currency?.identifier.lowercased(),
            receipt: receipt
        )
    }
    
//    private func completeVerifiedTransaction(transaction: Transaction, for storeProduct: Product, owner: KeyPair) async throws {
//        
//        
//        // TODO: Move below code into view model, convert StoreController to call
//        // completeVerifiedTransaction to pass the receipt and Product to the delegate
//        // and centralize all of the below code in the view model that call it in response
//        // to the delegate callback. The callback will be invoked on success in pay() or in
//        // Transaction.updates in response to async 'ask to buy' flow
//        
//        try await client.register(owner: owner)
//        try await client.completePurchase(
//            receipt: receipt,
//            productID: storeProduct.id,
//            price: price,
//            currency: currencyCode,
//            owner: owner
//        )
//        
//        Analytics.createAccountPayment(
//            price: price,
//            currency: currencyCode,
//            owner: owner.publicKey
//        )
//        
//        await transaction.finish() // Remove from queue
//    }
}

// MARK: - ReceiptDelegate -

private class ReceiptDelegate: NSObject, SKRequestDelegate {
    
    var completion: ((Result<(), Error>) -> Void)?

    override init() {
        super.init()
    }

    func requestDidFinish(_ request: SKRequest) {
        if let _ = Bundle.main.appStoreReceiptURL {
            print("[IAP] Refresh successful.")
            completion?(.success(()))
        } else {
            print("[IAP] Refresh finished but no receipt was found.")
            completion?(.failure(StoreController.Error.receiptNotFound))
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("[IAP] Refresh failed: \(error)")
        completion?(.failure(error))
    }
}


extension StoreController {
    struct Payment: Sendable, Equatable, Hashable {
        let productIdentifier: String
    }
}

extension StoreController {
    
    typealias FinishTransaction = () async -> Void
    
    enum PurchaseResult {
        case success(Purchase, FinishTransaction)
        case failed
        case pending
        case cancelled
    }
}

extension StoreController {
    struct Purchase: Codable, Hashable, Equatable, Sendable {
        let uniqueID: UUID
        let productID: String
        let price: Decimal?
        let currencyCode: String?
        let receipt: Data
    }
}

// MARK: - Errors -

extension StoreController {
    enum Error: Swift.Error {
        case productNotFound
        case productAlreadyPurchased
        case paymentsUnavailable
        case receiptNotFound
        case failedToLoadReceipt
        case unknown
    }
}

extension StoreController {
    static let mock = StoreController()
}
