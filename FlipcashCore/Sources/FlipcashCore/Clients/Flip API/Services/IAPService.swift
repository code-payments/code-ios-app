//
//  ActivityService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCoreAPI
import GRPC

class IAPService: CodeService<Flipcash_Iap_V1_IapNIOClient> {
    
    func completePurchase(receipt: Data, productID: String, fiatPaid: Fiat, owner: KeyPair, completion: @Sendable @escaping (Result<(), ErrorCompletePurchase>) -> Void) {
        trace(.send, components: "Receipt: \(receipt.count) bytes")
        
        let request = Flipcash_Iap_V1_OnPurchaseCompletedRequest.with {
            $0.platform = .apple
            $0.metadata = .with {
                $0.product  = productID
                $0.currency = fiatPaid.currencyCode.rawValue
                $0.amount   = Float(fiatPaid.doubleValue)
            }
            $0.receipt = .with { $0.value = receipt.base64EncodedString() }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.onPurchaseCompleted(request)
        call.handle(on: queue) { response in
            let error = ErrorCompletePurchase(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)", "Receipt: \(receipt.base64EncodedString())")
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

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Iap_V1_IapClientInterceptorFactoryProtocol {
    func makeOnPurchaseCompletedInterceptors() -> [GRPC.ClientInterceptor<FlipcashCoreAPI.Flipcash_Iap_V1_OnPurchaseCompletedRequest, FlipcashCoreAPI.Flipcash_Iap_V1_OnPurchaseCompletedResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Iap_V1_IapNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
