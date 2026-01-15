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

class CurrencyService: CodeService<Ocp_Currency_V1_CurrencyNIOClient> {
    
    func fetchExchangeRates(completion: @Sendable @escaping (Result<RatesSnapshot, Error>) -> Void) {
//        trace(.send)
        
        let call = service.getAllRates(Ocp_Currency_V1_GetAllRatesRequest())
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
    
    func fetchMint(mint: PublicKey, completion: @Sendable @escaping (Result<MintMetadata, Error>) -> Void) {
        fetchMints(mints: [mint]) {
            switch $0 {
            case .success(let mints):
                if mints.count == 1 {
                    completion(.success(mints.first!.value))
                } else {
                    completion(.failure(ErrorGeneric.unknown))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func fetchMints(mints: [PublicKey], completion: @Sendable @escaping (Result<[PublicKey: MintMetadata], Error>) -> Void) {
        trace(.send)
        
        var request = Ocp_Currency_V1_GetMintsRequest()
        request.addresses = mints.map(\.solanaAccountID)
        
        let call = service.getMints(request)
        call.handle(on: queue) { response in
            var mints: [PublicKey: MintMetadata] = [:]
            response.metadataByAddress.forEach { addressString, mint in
                if
                    let address = try? PublicKey(base58: addressString),
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

extension InterceptorFactory: Ocp_Currency_V1_CurrencyClientInterceptorFactoryProtocol {
    func makeGetAllRatesInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_GetAllRatesRequest, FlipcashAPI.Ocp_Currency_V1_GetAllRatesResponse>] {
        makeInterceptors()
    }
    
    func makeGetMintsInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_GetMintsRequest, FlipcashAPI.Ocp_Currency_V1_GetMintsResponse>] {
        makeInterceptors()
    }
    
    func makeGetHistoricalMintDataInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_GetHistoricalMintDataRequest, FlipcashAPI.Ocp_Currency_V1_GetHistoricalMintDataResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Ocp_Currency_V1_CurrencyNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
