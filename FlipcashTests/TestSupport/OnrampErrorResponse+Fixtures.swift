//
//  OnrampErrorResponse+Fixtures.swift
//  FlipcashTests
//

import Foundation
@testable import Flipcash

extension OnrampErrorResponse {

    /// Builds a fixture by decoding from JSON — `OnrampErrorResponse` and
    /// its `ErrorType` only have synthesized inits and a custom Decodable
    /// path, neither reachable across module boundaries even with
    /// `@testable`. `errorType` is the Coinbase raw value (e.g.
    /// `"ERROR_CODE_GUEST_INVALID_CARD"`).
    static func fixture(errorType: String = "ERROR_CODE_GUEST_INVALID_CARD") throws -> OnrampErrorResponse {
        let json: [String: Any] = [
            "correlationId": "test-correlation",
            "errorMessage": "test-error-message",
            "errorType": errorType,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(OnrampErrorResponse.self, from: data)
    }
}
