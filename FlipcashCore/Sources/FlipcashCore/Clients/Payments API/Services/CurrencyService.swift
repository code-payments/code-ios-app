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

private let logger = Logger(label: "flipcash.currency-service")

class CurrencyService: CodeService<Ocp_Currency_V1_CurrencyNIOClient>, @unchecked Sendable {
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
            
            completion(.success(mints))

        } failure: { error in
            completion(.failure(error))
        }
    }

    func fetchHistoricalMintData(
        mint: PublicKey,
        range: HistoricalRange,
        currencyCode: String,
        completion: @Sendable @escaping (Result<[HistoricalMintDataPoint], Error>) -> Void
    ) {
        logger.info("Fetching historical mint data")

        var request = Ocp_Currency_V1_GetHistoricalMintDataRequest()
        request.address = mint.solanaAccountID
        request.currencyCode = currencyCode
        request.predefinedRange = range

        let call = service.getHistoricalMintData(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                let dataPoints = response.data.map { data in
                    HistoricalMintDataPoint(
                        date: data.timestamp.date,
                        marketCap: data.marketCap
                    )
                }
                logger.info("Fetched historical mint data", metadata: ["count": "\(dataPoints.count)"])
                completion(.success(dataPoints))

            case .notFound:
                completion(.failure(ErrorRateHistory.notFound))

            case .missingData, .UNRECOGNIZED:
                completion(.failure(ErrorRateHistory.unknown))
            }
        } failure: { error in
            completion(.failure(error))
        }
    }

    /// Opens a server-streaming `Discover` RPC that pushes ranked currency batches.
    ///
    /// Each streamed response delivers a complete list of ``MintMetadata`` for the
    /// requested category. Uses `callOptions: .streaming` to avoid the 15-second
    /// default timeout. Cancel the returned ``StreamReference`` to tear down the stream.
    @discardableResult
    func discover(
        category: DiscoverCategory,
        handler: @Sendable @escaping ([MintMetadata]) -> Void
    ) -> StreamReference<Ocp_Currency_V1_DiscoverRequest, Ocp_Currency_V1_DiscoverResponse> {
        var request = Ocp_Currency_V1_DiscoverRequest()
        request.category = category.protoCategory

        let streamReference = StreamReference<Ocp_Currency_V1_DiscoverRequest, Ocp_Currency_V1_DiscoverResponse>()

        let stream = service.discover(request, callOptions: .streaming) { response in
            guard response.result == .ok else { return }
            let mints = response.mints.compactMap { try? MintMetadata($0) }
            handler(mints)
        }

        streamReference.stream = stream
        return streamReference
    }
}

// MARK: - Types -

public typealias HistoricalRange = Ocp_Currency_V1_PredefinedRange

public struct HistoricalMintDataPoint: Sendable {
    public let date: Date
    public let marketCap: Double
}

// MARK: - Errors -

public enum ErrorRateHistory: Int, Error {
    case ok
    case notFound
    case unknown
}

// MARK: - Interceptors -

extension InterceptorFactory: Ocp_Currency_V1_CurrencyClientInterceptorFactoryProtocol {
    func makeUpdateIconInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_UpdateIconRequest, FlipcashAPI.Ocp_Currency_V1_UpdateIconResponse>] {
        makeInterceptors()
    }
    
    func makeUpdateMetadataInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_UpdateMetadataRequest, FlipcashAPI.Ocp_Currency_V1_UpdateMetadataResponse>] {
        makeInterceptors()
    }
    
    func makeStreamLiveMintDataInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_StreamLiveMintDataRequest, FlipcashAPI.Ocp_Currency_V1_StreamLiveMintDataResponse>] {
        makeInterceptors()
    }

    func makeGetMintsInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_GetMintsRequest, FlipcashAPI.Ocp_Currency_V1_GetMintsResponse>] {
        makeInterceptors()
    }

    func makeGetHistoricalMintDataInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_GetHistoricalMintDataRequest, FlipcashAPI.Ocp_Currency_V1_GetHistoricalMintDataResponse>] {
        makeInterceptors()
    }

    func makeLaunchInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_LaunchRequest, FlipcashAPI.Ocp_Currency_V1_LaunchResponse>] {
        makeInterceptors()
    }

    func makeDiscoverInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_DiscoverRequest, FlipcashAPI.Ocp_Currency_V1_DiscoverResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Ocp_Currency_V1_CurrencyNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
