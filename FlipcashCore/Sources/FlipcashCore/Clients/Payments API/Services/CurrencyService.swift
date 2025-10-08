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
    
    func fetchExchangeRates(completion: @Sendable @escaping (Result<RatesSnapshot, Error>) -> Void) {
//        trace(.send)
        
        let call = service.getAllRates(Code_Currency_V1_GetAllRatesRequest())
        call.handle(on: queue) { response in
            let rates = response.rates.compactMap { key, value in
                try? Rate(
                    fx: Decimal(value),
                    currencyCode: key
                )
            }
            
            let snapshot = RatesSnapshot(
                date: response.asOf.date,
                rates: rates
            )
            
//            trace(.success, components: "\(rates.count) rates")
            completion(.success(snapshot))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    func fetchMints(mints: [PublicKey], completion: @Sendable @escaping (Result<[PublicKey: MintMetadata], Error>) -> Void) {
        trace(.send)
        
        var request = Code_Currency_V1_GetMintsRequest()
        request.addresses = mints.map(\.solanaAccountID)
        
        let call = service.getMints(request)
        call.handle(on: queue) { response in
            var mints: [PublicKey: MintMetadata] = [:]
            response.metadataByAddress.forEach { addressString, mint in
                if
                    let address = PublicKey(base58: addressString),
                    let metadata = try? MintMetadata(mint)
                {
                    mints[address] = metadata
                }
            }
            
            trace(.success, components: "\(mints.count) mints")
            completion(.success(mints))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
}

// MARK: - Types -

public struct RatesSnapshot: Sendable {
    public let date: Date
    public let rates: [Rate]
}

// MARK: - Errors -

public enum ErrorRateHistory: Int, Error {
    case ok
    case notFound
    case unknown
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Currency_V1_CurrencyClientInterceptorFactoryProtocol {
    func makeGetMintsInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Code_Currency_V1_GetMintsRequest, FlipcashAPI.Code_Currency_V1_GetMintsResponse>] {
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
