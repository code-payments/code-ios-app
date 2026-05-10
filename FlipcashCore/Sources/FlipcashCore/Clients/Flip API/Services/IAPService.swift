//
//  ActivityService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.iap-service")

class IAPService: CodeService<Flipcash_Iap_V1_IapNIOClient> {

    func completePurchase(receipt: Data, productID: String, price: Double, currency: String, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCompletePurchase>) -> Void) {
        logger.info("Completing in-app purchase", metadata: ["receiptSize": "\(receipt.count) bytes"])

        let request = Flipcash_Iap_V1_OnPurchaseCompletedRequest.with {
            $0.platform = .apple
            $0.metadata = .with {
                $0.product  = productID
                $0.currency = currency
                $0.amount   = price
            }
            $0.receipt = .with { $0.value = receipt.base64EncodedString() }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.onPurchaseCompleted(request)
        call.handle(on: queue) { response in
            let error = ErrorCompletePurchase(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                logger.info("In-app purchase completed successfully")
                completion(.success(()))
            } else {
                logger.error("Failed to complete in-app purchase", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }

        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorCompletePurchase: Int, Error {
    case ok
    case denied
    case invalidReceipt
    case invalidMetadata
    case unknown = -1
}

extension ErrorCompletePurchase: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .invalidReceipt, .invalidMetadata: false
        case .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Iap_V1_IapClientInterceptorFactoryProtocol {
    func makeOnPurchaseCompletedInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Iap_V1_OnPurchaseCompletedRequest, Flipcash_Iap_V1_OnPurchaseCompletedResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Iap_V1_IapNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
