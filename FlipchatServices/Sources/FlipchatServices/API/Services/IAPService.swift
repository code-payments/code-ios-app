//
//  IAPService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatAPI
import GRPC

class IAPService: FlipchatService<Flipchat_Iap_V1_IapNIOClient> {
    
    func notifyPurchaseCompleted(receipt: Data, owner: KeyPair, completion: @escaping (Result<(), ErrorPurchaseCompleted>) -> Void) {
        trace(.send, components: "Receipt: \(receipt.count) bytes")
        
        let request = Flipchat_Iap_V1_OnPurchaseCompletedRequest.with {
            $0.platform = .apple
            $0.receipt = .with { $0.value = receipt.base64EncodedString() }
            $0.auth = owner.authFor(message: $0)
        }
        
        let call = service.onPurchaseCompleted(request)
        
        call.handle(on: queue) { response in
            let error = ErrorPurchaseCompleted(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success)
                completion(.success(()))
            } else {
                trace(.failure, components: "Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorPurchaseCompleted: Int, Error {
    case ok
    case denied
    case invalidReceipt
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipchat_Iap_V1_IapClientInterceptorFactoryProtocol {
    func makeOnPurchaseCompletedInterceptors() -> [GRPC.ClientInterceptor<FlipchatAPI.Flipchat_Iap_V1_OnPurchaseCompletedRequest, FlipchatAPI.Flipchat_Iap_V1_OnPurchaseCompletedResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipchat_Iap_V1_IapNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
