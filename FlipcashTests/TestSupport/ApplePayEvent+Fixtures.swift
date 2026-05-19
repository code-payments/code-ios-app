//
//  ApplePayEvent+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension ApplePayEvent {

    /// Builds a synthetic event the WebView would otherwise have decoded
    /// from Coinbase's onramp postMessage payload. `errorMessage` populates
    /// `EventData.errorMessage` so tests can assert it propagates into the
    /// thrown `serverRejected(_:)`.
    static func fixture(
        _ event: ApplePayEvent.Event,
        errorMessage: String? = nil
    ) -> ApplePayEvent {
        let data: ApplePayEvent.EventData? = errorMessage.map {
            .init(errorCode: nil, errorMessage: $0)
        }
        return ApplePayEvent(name: event.rawValue, data: data)
    }
}
