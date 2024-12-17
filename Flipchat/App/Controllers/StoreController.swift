//
//  StoreController.swift
//  Code
//
//  Created by Dima Bart on 2024-12-10.
//

import Foundation
import StoreKit

protocol StoreControllerDelegate: AnyObject {
    func handlePayment(payment: Result<StoreController.Payment, Error>)
    func didLoadPrices(products: [StoreController.Product: String])
}

@MainActor
class StoreController: NSObject, ObservableObject {
    
    private var products: [String: SKProduct] = [:]
    
    private weak var delegate: StoreControllerDelegate?
    
    // MARK: - Init -
    
    init(delegate: StoreControllerDelegate) {
        self.delegate = delegate
        
        super.init()
    }
    
    deinit {
        print("Deallocating StoreController.")
    }
    
    func loadProducts() {
        guard SKPaymentQueue.canMakePayments() else {
            return
        }
        
        let request = SKProductsRequest(productIdentifiers: Set(Product.allCases.map { $0.rawValue }))
        request.delegate = self
        request.start()
    }
    
    // MARK: - Setters -
    
    private func setProducts(products: [String: SKProduct]) {
        self.products = products
    }
    
    // MARK: - Actions -

    func pay(for product: Product) throws {
        guard let storeProduct = products[product.rawValue] else {
            print("[IAP] Can't make purchases.")
            throw Error.productNotFound
        }
        
        let payment = SKPayment(product: storeProduct)
        
        SKPaymentQueue.default().add(self)
        SKPaymentQueue.default().add(payment)
    }
    
    func processPayment(payment: Result<StoreController.Payment, Swift.Error>) {
        print("[IAP] Received payment: \(payment)")
        delegate?.handlePayment(payment: payment)
    }
}

// MARK: - Products -

extension StoreController {
    enum Product: String, CaseIterable {
        case createAccount = "com.flipchat.iap.createAccount"
    }
}

extension StoreController {
    struct Payment: Sendable, Equatable, Hashable {
        let productIdentifier: String
    }
}

// MARK: - Errors -

extension StoreController {
    enum Error: Swift.Error {
        case productNotFound
        case paymentsUnavailable
        case unknown
    }
}

// MARK: - Delegate -

extension StoreController: SKRequestDelegate, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    nonisolated
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        let products = response.products.elementsKeyed(by: \.productIdentifier)
        Task {
            await setProducts(products: products)
            
            var container: [Product: String] = [:]
            for (id, product) in products {
                container[Product(rawValue: id)!] = localizedPrice(for: product)
            }
            
            Task { @MainActor [weak self] in
                self?.delegate?.didLoadPrices(products: container)
                print("[IAP] Loaded products: \(response.products.map { $0.productIdentifier })")
            }
        }
    }
    
    nonisolated
    private func localizedPrice(for product: SKProduct) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price)
    }
    
    nonisolated
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        let paymentQueue = SKPaymentQueue.default()
        
        transactions.forEach {
            switch $0.transactionState {
            case .purchased, .restored:
                paymentQueue.finishTransaction($0)
                
                let payment = Payment(
                    productIdentifier: $0.payment.productIdentifier
                )
                
                Task {
                    await processPayment(payment: .success(payment))
                }
                
            case .failed:
                paymentQueue.finishTransaction($0)
                let error = $0.error ?? Error.unknown
                Task {
                    await processPayment(payment: .failure(error))
                }
                
            case .purchasing, .deferred:
                break
                
            @unknown default:
                break
            }
        }
    }
}
