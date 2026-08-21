//
//  Analytics.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import Mixpanel
import Bugsnag
import FlipcashCore

private let logger = Logger(label: "flipcash.analytics")

typealias AnalyticsValue = MixpanelType

protocol AnalyticsEvent: Sendable {
    var eventName: String { get }
}

extension AnalyticsEvent where Self: RawRepresentable<String> {
    var eventName: String { rawValue }
}

enum Analytics {

    private static var isEnabled = false

    /// Resolves a mint's base58 address to its ticker symbol. Installed once at
    /// session start (see `SessionAuthenticator.completeLogin`) so no call site has
    /// to look a symbol up; nil before login, and nil per-mint when the mint isn't
    /// cached locally — in which case the symbol property is omitted, never blank.
    static var tokenSymbolResolver: (@MainActor (String) -> String?)?

    static func initialize() {
        let apiKey = try? InfoPlist.value(for: "mixpanel").value(for: "apiKey").string()
        if let apiKey {
            logger.info("Initializing Mixpanel")
            Mixpanel.initialize(token: apiKey, trackAutomaticEvents: true)
            isEnabled = true
        } else {
            logger.error("Failed to initialize Mixpanel. No API key found in Info.plist")
        }
    }

    static func track(event: some AnalyticsEvent, properties: [Property: AnalyticsValue]? = nil, error: Error? = nil) {
        guard isEnabled else { return }

        var container: [String: AnalyticsValue] = [:]

        let resolved: [Property: AnalyticsValue]
        if let properties, let tokenSymbolResolver {
            resolved = withTokenSymbols(properties, resolve: tokenSymbolResolver)
        } else {
            resolved = properties ?? [:]
        }

        resolved.forEach { key, value in
            container[key.rawValue] = value
        }

        if let error {
            let swiftError = error as NSError
            container["Error"] = "\(swiftError.domain).\(error):\(swiftError.code)"
        }

        mixpanel.track(event: event.eventName, properties: container)
    }

    /// Pairs every mint-valued property with the symbol property that shadows it.
    private static let mintProperties: [(mint: Property, symbol: Property)] = [
        (.mint, .tokenSymbol),
        (.paymentMint, .paymentTokenSymbol),
    ]

    /// Adds the ticker symbol beside each mint `properties` carries. An unresolvable
    /// mint leaves its symbol property absent — an empty or placeholder value would
    /// be indistinguishable from a real symbol in a Mixpanel breakdown.
    static func withTokenSymbols(
        _ properties: [Property: AnalyticsValue],
        resolve: (String) -> String?
    ) -> [Property: AnalyticsValue] {
        var enriched = properties
        for pair in mintProperties {
            guard let base58 = properties[pair.mint] as? String,
                  let symbol = resolve(base58) else { continue }
            enriched[pair.symbol] = symbol
        }
        return enriched
    }
}

// MARK: - Identity -

extension Analytics {
    static func setIdentity(_ userID: UserID) {
        guard isEnabled else { return }
        // Ensure that this runs after `initialize` has been called
        // on all the tracking platforms
        DispatchQueue.main.async {
            let userID = userID.data.hexString()
            
            // Bugsnag
            Bugsnag.setUser(userID, withEmail: userID, andName: nil)
            
            // Mixpanel
            mixpanel.identify(distinctId: userID)
            mixpanel.people.set(property: "$email", to: "userID:\(userID)")
        }
    }
}

// MARK: - Private -

private extension Analytics {
    static var mixpanel: MixpanelInstance {
        Mixpanel.mainInstance()
    }
}
