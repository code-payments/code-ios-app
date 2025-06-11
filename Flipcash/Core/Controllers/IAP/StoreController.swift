//
//  StoreController.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import FlipcashCore
import StoreKit

@MainActor
class StoreController: NSObject, ObservableObject {
    
    @Published private(set) var products: [String: Product] = [:]
    
    private var updates: Task<Void, Never>?
    
    private let client: FlipClient
    
    // MARK: - Init -
    
    init(client: FlipClient) {
        self.client = client
        
        super.init()
        
        loadProductsIfNeeded()
        listenForTransactionUpdates()
    }
    
    private func listenForTransactionUpdates() {
        updates = Task { @MainActor in
            for await update in Transaction.updates {
                if let transaction = try? update.payloadValue {
                    print("[IAP] Finished transaction: \(transaction.id)")
                    await transaction.finish()
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

    func pay(for product: IAPProduct, owner: KeyPair) async throws -> PurchaseResult {
        if products.isEmpty {
            print("[IAP] Loading products before purchase.")
            try await loadProducts()
        }
        
        guard let storeProduct = products[product.rawValue] else {
            print("[IAP] Can't make purchases.")
            throw Error.productNotFound
        }
        
        guard await Transaction.latest(for: product.rawValue) == nil else {
            print("[IAP] Product already purchased: \(product.rawValue)")
            throw Error.productAlreadyPurchased
        }
        
        let result = try await storeProduct.purchase()
        switch result {
        case .success(let purchaseResult):
            
            // Handle purchase result
            switch purchaseResult {
            case .unverified(_, let error):
                print("[IAP] Purchase could not be verified: \(error)")
                try await purchaseResult.payloadValue.finish() // Remove from queue
                return .failed
                
            case .verified(let tx):
                try await completeVerifiedTransaction(
                    transaction: tx,
                    for: storeProduct,
                    owner: owner
                )
                return .success(product)
            }
            
        case .userCancelled:
            print("[IAP] Purchase cancelled")
            return .cancelled
            
        case .pending:
            // TODO: Handle pending transactions
            fatalError("[IAP] (UNSUPPORTED) Purchase pending")
            
        @unknown default:
            print("[IAP] Unknown purchase result: \(result)")
            return .failed
        }
    }
    
    private func completeVerifiedTransaction(transaction: Transaction, for product: Product, owner: KeyPair) async throws {
        print("[IAP] Purchase success. Tx: \(transaction.id)")
        
        try await refreshReceipt()
        
        let receipt = try await getReceipt()
        print("[IAP] Receipt: \(receipt.base64EncodedString())")
        
        let price = product.price.doubleValue
        let currencyCode = product.priceFormatStyle.currencyCode.lowercased()
        
        try await client.register(owner: owner)
        try await client.completePurchase(
            receipt: receipt,
            productID: product.id,
            price: price,
            currency: currencyCode,
            owner: owner
        )
        
        Analytics.createAccountPayment(
            price: price,
            currency: currencyCode,
            owner: owner.publicKey
        )
        
        await transaction.finish() // Remove from queue
    }
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
    enum PurchaseResult {
        case success(IAPProduct)
        case failed
        case cancelled
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
    static let mock = StoreController(client: .mock)
}
