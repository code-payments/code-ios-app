//
//  SettingsService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.settings-service")

class SettingsService: CodeService<Flipcash_Settings_V1_SettingsNIOClient> {

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

        let call = service.updateSettings(request)
        call.handle(on: queue, completion: completion) { response in
            let error = ErrorUpdateSettings(rawValue: response.result.rawValue) ?? .unknown
            guard error == .ok else {
                logger.error("Failed to update settings", metadata: ["error": "\(error)"])
                return .failure(error)
            }
            logger.info("Settings updated successfully")
            return .success(())
        }
    }
}

// MARK: - Errors -

public enum ErrorUpdateSettings: Int, Error, Equatable, Sendable {
    case ok
    case denied
    case invalidLocale
    case invalidRegion
    case unknown          = -1
    case transportFailure = -2
}

extension ErrorUpdateSettings: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .invalidLocale, .invalidRegion, .transportFailure: false
        case .unknown: true
        }
    }
}

extension ErrorUpdateSettings: TransportClassifiableError {
    public static func from(transportError status: GRPCStatus) -> ErrorUpdateSettings {
        status.code.isTransientNetworkError ? .transportFailure : .unknown
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Settings_V1_SettingsClientInterceptorFactoryProtocol {
    func makeUpdateSettingsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Settings_V1_UpdateSettingsRequest, Flipcash_Settings_V1_UpdateSettingsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Settings_V1_SettingsNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
