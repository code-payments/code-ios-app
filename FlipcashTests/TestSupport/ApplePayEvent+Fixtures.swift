//
//  ApplePayEvent+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension ApplePayEvent {

    /// Builds a synthetic event the WebView would otherwise have decoded
    /// from Coinbase's onramp postMessage payload. `errorCode` and
    /// `errorMessage` populate `EventData` so tests can assert how the
    /// error path maps Coinbase's raw code onto `OnrampErrorResponse.ErrorType`
    /// before throwing `externalRejected(title:subtitle:)`.
    static func fixture(
        _ event: ApplePayEvent.Event,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) -> ApplePayEvent {
        let data: ApplePayEvent.EventData?
        if errorCode == nil && errorMessage == nil {
            data = nil
        } else {
            data = .init(errorCode: errorCode, errorMessage: errorMessage)
        }
        return ApplePayEvent(name: event.rawValue, data: data)
    }
}
