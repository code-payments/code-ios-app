//
//  StoreController.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import FlipchatServices
import StoreKit

@MainActor
class StoreController: NSObject, ObservableObject {
    
    @Published private(set) var products: [String: Product] = [:]
    
    private var updates: Task<Void, Never>?
    
    private let client: FlipchatClient
    private let owner: KeyPair
    
    // MARK: - Init -
    
    init(client: FlipchatClient, owner: KeyPair) {
        self.client = client
        self.owner = owner
        
        super.init()
        
        Task {
            try await loadProducts()
        }
        
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
        let products = try await Product.products(for: FlipchatProduct.productIDs)
        self.products = products.elementsKeyed(by: \.id)
        print("[IAP] Loaded products:")
        products.forEach {
            print("\($0.id): \($0.formattedPrice) - \($0.displayName)")
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
            let request = SKReceiptRefreshRequest()
            delegate.completion = {
                c.resume(with: $0)
            }
            
            request.delegate = delegate
            request.start()
        }
    }
    
    // MARK: - Actions -

    func pay(for product: FlipchatProduct) async throws -> PurchaseResult {
        if products.isEmpty {
            print("[IAP] Loading products before purchase.")
            try await loadProducts()
        }
        
        guard let storeProduct = products[product.rawValue] else {
            print("[IAP] Can't make purchases.")
            throw Error.productNotFound
        }
        
        let result = try await storeProduct.purchase()
        switch result {
        case .success(let purchaseResult):
            
            switch purchaseResult {
            case .unverified(_, let error):
                print("[IAP] Purchase could not be verified: \(error)")
                return .failed
                
            case .verified(let tx):
                let receipt = try await getReceipt()
                
                print("[IAP] Purchase success. Tx: \(tx.id)")
                print("[IAP] Receipt: \(receipt.count) bytes")
                
                try await client.notifyPurchaseCompleted(
                    receipt: receipt,
                    owner: owner
                )
                
                let transaction = try purchaseResult.payloadValue
                await transaction.finish()
                
                return .success(product)
            }
            
        case .userCancelled:
            print("[IAP] Purchase cancelled")
            return .cancelled
            
        case .pending:
            fatalError("[IAP] (UNSUPPORTED) Purchase pending")
            
        @unknown default:
            print("[IAP] Unknown purchase result: \(result)")
            return .failed
        }
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

// MARK: - Products -

enum FlipchatProduct: String, CaseIterable, Hashable, Equatable {
    
    case createAccount = "com.flipchat.iap.createAccount"
    
    static var productIDs: Set<String> {
        Set(allCases.map { $0.rawValue })
    }
}

extension StoreController {
    struct Payment: Sendable, Equatable, Hashable {
        let productIdentifier: String
    }
}

extension StoreController {
    enum PurchaseResult {
        case success(FlipchatProduct)
        case failed
        case cancelled
    }
}

// MARK: - Errors -

extension StoreController {
    enum Error: Swift.Error {
        case productNotFound
        case paymentsUnavailable
        case receiptNotFound
        case failedToLoadReceipt
        case unknown
    }
}

extension Product {
    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceFormatStyle.locale
        
        return formatter.string(from: price) ?? "n/a"
    }
}

extension StoreController {
    static let mock = StoreController(client: .mock, owner: .mock)
}
