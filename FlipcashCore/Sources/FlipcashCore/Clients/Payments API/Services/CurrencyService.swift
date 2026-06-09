//
//  CurrencyService.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.currency-service")

final class CurrencyService: Sendable {

    private let service: Ocp_Currency_V1_Currency.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Ocp_Currency_V1_Currency.Client(wrapping: client)
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
        var request = Ocp_Currency_V1_GetMintsRequest()
        request.addresses = mints.map(\.solanaAccountID)

        Task { @MainActor in
            do {
                let response = try await service.getMints(request, options: .unaryDefault)
                var result: [PublicKey: MintMetadata] = [:]
                response.metadataByAddress.forEach { addressString, mint in
                    if
                        let address = try? PublicKey(base58: addressString),
                        let metadata = try? MintMetadata(mint)
                    {
                        result[address] = metadata
                    }
                }
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
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

        Task { @MainActor in
            do {
                let response = try await service.getHistoricalMintData(request, options: .unaryDefault)
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
            } catch let error as RPCError {
                completion(.failure(ErrorRateHistory.from(transportError: error)))
            } catch {
                completion(.failure(ErrorRateHistory.unknown))
            }
        }
    }

    /// Opens a server-streaming `Discover` RPC that pushes ranked currency batches.
    ///
    /// Each streamed response delivers a complete list of ``MintMetadata`` for the
    /// requested category. Streaming gets no deadline. Cancel the returned
    /// ``ServerGRPCStream`` to tear down the stream.
    @discardableResult
    func discover(
        category: DiscoverCategory,
        handler: @Sendable @escaping ([MintMetadata]) -> Void,
        onComplete: @Sendable @escaping (Result<Void, any Error>) -> Void = { _ in }
    ) -> ServerGRPCStream {
        let request = Ocp_Currency_V1_DiscoverRequest.with {
            $0.category = category.protoCategory
        }

        let stream = ServerGRPCStream()
        stream.open(onComplete: onComplete) {
            try await self.service.discover(request) { response in
                for try await message in response.messages {
                    guard message.result == .ok else { continue }
                    let mints = message.mints.compactMap { try? MintMetadata($0) }
                    handler(mints)
                }
            }
        }
        return stream
    }

    func checkAvailability(
        name: String,
        completion: @Sendable @escaping (Result<Bool, Error>) -> Void
    ) {
        logger.info("Checking currency name availability")

        var request = Ocp_Currency_V1_CheckAvailabilityRequest()
        request.name = name

        Task { @MainActor in
            do {
                let response = try await service.checkAvailability(request, options: .unaryDefault)
                switch response.result {
                case .ok:
                    logger.info("Currency availability check", metadata: ["is_available": "\(response.isAvailable)"])
                    completion(.success(response.isAvailable))
                case .UNRECOGNIZED:
                    logger.error("Availability check returned unrecognized result")
                    completion(.failure(ErrorGeneric.unknown))
                }
            } catch {
                logger.error("Availability check gRPC error", metadata: ["error": "\(error)"])
                completion(.failure(error))
            }
        }
    }

    /// Opens the bidirectional `StreamLiveMintData` RPC, returning a retained,
    /// cancellable handle the caller drives with `sendMessage`. Streaming gets no
    /// deadline. `onResponse` fires for every inbound message; `onComplete` fires
    /// once with the terminal result (clean close or transport error).
    func openLiveMintDataStream(
        onResponse: @escaping @Sendable (Ocp_Currency_V1_StreamLiveMintDataResponse) -> Void,
        onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) -> BidirectionalGRPCStream<Ocp_Currency_V1_StreamLiveMintDataRequest, Ocp_Currency_V1_StreamLiveMintDataResponse> {
        let stream = BidirectionalGRPCStream<Ocp_Currency_V1_StreamLiveMintDataRequest, Ocp_Currency_V1_StreamLiveMintDataResponse>()
        stream.open(onResponse: onResponse, onComplete: onComplete) { requests, onResponse in
            try await self.service.streamLiveMintData(
                requestProducer: { writer in
                    for await request in requests {
                        try await writer.write(request)
                    }
                },
                onResponse: { streamResponse in
                    for try await message in streamResponse.messages {
                        onResponse(message)
                    }
                }
            )
        }
        return stream
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

        Task { @MainActor in
            do {
                let response = try await service.launch(request, options: .unaryDefault)
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
            } catch {
                logger.error("Launch gRPC error", metadata: ["error": "\(error)"])
                completion(.failure(.network(error)))
            }
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
    case unknown          = -1
    case transportFailure = -2
}

public enum ErrorLaunchCurrency: Error, Sendable {
    case denied
    case nameExists
    case invalidIcon
    case unknown
    case network(Error)
}

extension ErrorRateHistory: ServerError, TransportClassifiableError {
    public var isReportable: Bool {
        switch self {
        case .ok, .notFound, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorLaunchCurrency: ServerError {
    public var isReportable: Bool {
        switch self {
        case .denied, .nameExists, .invalidIcon: false
        case .unknown: true
        case .network(let error): (error as? ServerError)?.isReportable ?? true
        }
    }
}
