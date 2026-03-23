//
//  FlipClient+Settings.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    public func updateSettings(locale: String?, region: String?, owner: KeyPair) async throws {
        try await withCheckedThrowingContinuation { c in
            settingsService.updateSettings(locale: locale, region: region, owner: owner) { c.resume(with: $0) }
        }
    }
}
