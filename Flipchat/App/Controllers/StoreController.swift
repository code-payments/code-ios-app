//
//  StoreController.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import Foundation
import StoreKit

@MainActor
class StoreController: NSObject, ObservableObject {
    
    @Published private(set) var products: [String: Product] = [:]
    
    private var updates: Task<Void, Never>?
    
    // MARK: - Init -
    
    override init() {
        super.init()
        
        Task {
            try await loadProducts()
        }
        
        updates = Task {
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
    
//    func fetchReceipt() throws -> Data {
//        let f = FileManager.default
//        
//        guard let receiptURL = Bundle.main.appStoreReceiptURL, f.fileExists(atPath: receiptURL.path) else {
//            throw Error.receiptNotFound
//        }
//
//        do {
//            let receiptData = try Data(contentsOf: receiptURL)
////            let receiptBase64 = receiptData.base64EncodedString()
//            return receiptData
//        } catch {
//            throw Error.failedToLoadReceipt
//        }
//    }
    
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
                print("[IAP] Purchase success. Tx: \(tx.id)")
                print("[IAP] Transaction: \(String(data: tx.jsonRepresentation, encoding: .utf8) ?? "nil")")
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
        
        return formatter.string(from: price)!
    }
}

extension StoreController {
    static let mock = StoreController()
}

// MARK: - Delegate -

//extension StoreController: SKRequestDelegate, SKProductsRequestDelegate, SKPaymentTransactionObserver {
//    
//    nonisolated
//    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
//        let products = response.products.elementsKeyed(by: \.productIdentifier)
//        Task {
//            await setProducts(products: products)
//            
//            var container: [FlipchatProduct: String] = [:]
//            for (id, product) in products {
//                container[FlipchatProduct(rawValue: id)!] = localizedPrice(for: product)
//            }
//            
//            Task { @MainActor [weak self] in
//                self?.delegate?.didLoadPrices(products: container)
//                print("[IAP] Loaded products: \(response.products.map { $0.productIdentifier })")
//            }
//        }
//    }
//    
//    nonisolated
//    private func localizedPrice(for product: SKProduct) -> String? {
//        let formatter = NumberFormatter()
//        formatter.numberStyle = .currency
//        formatter.locale = product.priceLocale
//        return formatter.string(from: product.price)
//    }
//    
//    nonisolated
//    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
//        let paymentQueue = SKPaymentQueue.default()
//        
//        transactions.forEach {
//            switch $0.transactionState {
//            case .purchased, .restored:
//                paymentQueue.finishTransaction($0)
//                
//                let payment = Payment(
//                    productIdentifier: $0.payment.productIdentifier
//                )
//                
//                Task {
//                    await processPayment(payment: .success(payment))
//                }
//                
//            case .failed:
//                paymentQueue.finishTransaction($0)
//                let error = $0.error ?? Error.unknown
//                Task {
//                    await processPayment(payment: .failure(error))
//                }
//                
//            case .purchasing, .deferred:
//                break
//                
//            @unknown default:
//                break
//            }
//        }
//    }
//}
