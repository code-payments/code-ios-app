//
//  CurrencyService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPC
import NIO

class CurrencyService: CodeService<Code_Currency_V1_CurrencyNIOClient> {
    
    func fetchExchangeRates(completion: @escaping (Result<([Rate], Date), Error>) -> Void) {
//        trace(.send)
        
        let call = service.getAllRates(Code_Currency_V1_GetAllRatesRequest())
        call.handle(on: queue) { response in
            let rates = response.rates.compactMap { key, value in
                Rate(
                    fx: Decimal(value),
                    currencyCode: key
                )
            }
            
//            trace(.success, components: "\(rates.count) rates")
            completion(.success((rates, response.asOf.date)))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
}

public enum ErrorRateHistory: Int, Error {
    case ok
    case notFound
    case unknown
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Currency_V1_CurrencyClientInterceptorFactoryProtocol {
    func makeGetAllRatesInterceptors() -> [ClientInterceptor<Code_Currency_V1_GetAllRatesRequest, Code_Currency_V1_GetAllRatesResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Currency_V1_CurrencyNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
