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

    func checkAvailability(
        name: String,
        completion: @Sendable @escaping (Result<Bool, Error>) -> Void
    ) {
        logger.info("Checking currency name availability")

        var request = Ocp_Currency_V1_CheckAvailabilityRequest()
        request.name = name

        let call = service.checkAvailability(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                logger.info("Currency availability check", metadata: ["is_available": "\(response.isAvailable)"])
                completion(.success(response.isAvailable))
            case .UNRECOGNIZED:
                logger.error("Availability check returned unrecognized result")
                completion(.failure(ErrorGeneric.unknown))
            }
        } failure: { error in
            logger.error("Availability check gRPC error", metadata: ["error": "\(error)"])
            completion(.failure(error))
        }
    }

    func launch(
        name: String,
        description: String?,
        billCustomization: Ocp_Currency_V1_BillCustomization?,
        icon: Data?,
        nameAttestation: ModerationAttestation,
        descriptionAttestation: ModerationAttestation?,
        iconAttestation: ModerationAttestation?,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<PublicKey, ErrorLaunchCurrency>) -> Void
    ) {
        logger.info("Launching currency")

        var request = Ocp_Currency_V1_LaunchRequest()
        request.owner = owner.publicKey.solanaAccountID
        request.name = name
        if let description { request.description_p = description }
        if let billCustomization { request.billCustomization = billCustomization }
        if let icon { request.icon = icon }
        request.nameModerationAttestation = nameAttestation.currencyProto
        if let descriptionAttestation { request.descriptionModerationAttestation = descriptionAttestation.currencyProto }
        if let iconAttestation { request.iconModerationAttestation = iconAttestation.currencyProto }
        request.signature = request.sign(with: owner)

        let call = service.launch(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                guard let mint = try? PublicKey(response.mint.value) else {
                    logger.error("Launch succeeded but mint key invalid")
                    completion(.failure(.unknown))
                    return
                }
                logger.info("Currency launched", metadata: ["mint": "\(mint.base58)"])
                completion(.success(mint))

            case .denied:
                logger.error("Currency launch denied")
                completion(.failure(.denied))

            case .nameExists:
                logger.info("Currency launch: name exists")
                completion(.failure(.nameExists))

            case .invalidIcon:
                logger.error("Currency launch: invalid icon")
                completion(.failure(.invalidIcon))

            case .UNRECOGNIZED:
                logger.error("Launch returned unrecognized result")
                completion(.failure(.unknown))
            }
        } failure: { error in
            logger.error("Launch gRPC error", metadata: ["error": "\(error)"])
            completion(.failure(.network(error)))
        }
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

public enum ErrorLaunchCurrency: Error, Sendable {
    case denied
    case nameExists
    case invalidIcon
    case unknown
    case network(Error)
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

    func makeCheckAvailabilityInterceptors() -> [GRPC.ClientInterceptor<FlipcashAPI.Ocp_Currency_V1_CheckAvailabilityRequest, FlipcashAPI.Ocp_Currency_V1_CheckAvailabilityResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Ocp_Currency_V1_CurrencyNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
