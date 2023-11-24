//
//  CurrencyService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import GRPC
import NIO

class CurrencyService: CodeService<Code_Currency_V1_CurrencyNIOClient> {
    
    func fetchExchangeRates(completion: @escaping (Result<([Rate], Date), Error>) -> Void) {
//        trace(.send)
        
        let call = service.getAllRates(Code_Currency_V1_GetAllRatesRequest())
        call.handle(on: queue) { response in
            var rates = response.rates.compactMap { key, value in
                Rate(
                    fx: Decimal(value),
                    currencyCode: key
                )
            }
            
            // Insert 1:1 rate for Kin if isn't passed in
            if rates.firstIndex(where: { $0.currency == .kin }) == nil {
                rates.append(
                    Rate(fx: 1, currency: .kin)
                )
            }
            
//            trace(.success, components: "\(rates.count) rates")
            completion(.success((rates, response.asOf.date)))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    func fetchExchangeRateHistory(range: DateRange, interval: DateRange.Interval, completion: @escaping (Result<[Rate], ErrorRateHistory>) -> Void) {
        trace(.send)
        
        let currency = CurrencyCode.usd
        
        var request = Code_Currency_V1_GetExchangeRateHistoryRequest()
        request.forSymbol = currency.rawValue
        request.interval = interval.exchangeInterval
        request.start = .init(date: range.start)
        
        if let end = range.end {
            request.end = .init(date: end)
        }
        
        let call = service.getExchangeRateHistory(request)
        call.handle(on: queue) { response in
            let error = ErrorRateHistory(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                let rates = response.items.compactMap {
                    Rate(
                        fx: Decimal($0.rate),
                        currency: currency
                    )
                }
                
                trace(.success, components: "\(response.items.count) historical rates")
                completion(.success(rates))
            } else {
                trace(.success, components: "Failed to fetch historical rates: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
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
    func makeGetExchangeRateHistoryInterceptors() -> [ClientInterceptor<Code_Currency_V1_GetExchangeRateHistoryRequest, Code_Currency_V1_GetExchangeRateHistoryResponse>] {
        makeInterceptors()
    }
    
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
