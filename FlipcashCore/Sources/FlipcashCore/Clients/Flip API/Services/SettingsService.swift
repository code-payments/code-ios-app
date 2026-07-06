//
//  SettingsService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPCCore

private let logger = Logger(label: "flipcash.settings-service")

final class SettingsService: Sendable {

    private let service: Flipcash_Settings_V1_Settings.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_Settings_V1_Settings.Client(wrapping: client)
    }

    func updateSettings(locale: String?, region: String?, owner: KeyPair, completion: @Sendable @escaping (Result<Void, ErrorUpdateSettings>) -> Void) {
        logger.info("Updating settings", metadata: [
            "locale": "\(locale ?? "nil")",
            "region": "\(region ?? "nil")"
        ])

        let request = Flipcash_Settings_V1_UpdateSettingsRequest.with {
            if let locale {
                $0.locale = .with { $0.value = locale }
            }
            if let region {
                $0.region = .with { $0.value = region }
            }
            $0.auth = owner.authFor(message: $0)
        }

        Task {
            do {
                let response = try await service.updateSettings(request, options: .unaryDefault)
                let error = ErrorUpdateSettings(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("Failed to update settings", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                logger.info("Settings updated successfully")
                await MainActor.run { completion(.success(())) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorUpdateSettings: Int, Error {
    case ok
    case denied
    case invalidLocale
    case invalidRegion
    case unknown          = -1
    case transportFailure = -2
    case cancelled = -3
}

extension ErrorUpdateSettings: ServerError, TransportClassifiableError {
    public var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .transportFailure: .suppressed
        case .cancelled: .info
        case .denied, .invalidLocale, .invalidRegion: .info
        case .unknown: .error
        }
    }
}
