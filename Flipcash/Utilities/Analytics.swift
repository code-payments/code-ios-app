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

    /// Test-only replacement for the Mixpanel event call; while set, events are handed to it
    /// even though Mixpanel was never initialized.
    static var sendOverride: ((String, [String: AnalyticsValue]) -> Void)?

    /// Test-only replacement for the Mixpanel people increment, with the same rules as
    /// `sendOverride`.
    static var incrementOverride: ((String, Double) -> Void)?

    static func track(event: some AnalyticsEvent, properties: [Property: AnalyticsValue]? = nil, error: Error? = nil) {
        guard isEnabled || sendOverride != nil else { return }

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
            container["Error"] = errorValue(error)
        }

        send(event.eventName, container)
    }

    /// Sends an event built by the shared contract, adding token symbols and the iOS
    /// `Error` format exactly as `track(event:properties:error:)` does.
    static func track(_ event: TrackedEvent, error: Error? = nil) {
        guard isEnabled || sendOverride != nil else { return }

        var container: [String: AnalyticsValue] = event.scalarProperties.mapValues { scalar in
            switch scalar {
            case .text(let value):   value
            case .number(let value): value
            case .flag(let value):   value
            }
        }

        if let tokenSymbolResolver {
            container = withTokenSymbols(container, resolve: tokenSymbolResolver)
        }

        if let error {
            container["Error"] = errorValue(error)
        }

        send(event.name, container)
    }

    /// The `Error` property value iOS sends for `error`: its domain, description and code.
    static func errorValue(_ error: Error) -> String {
        let swiftError = error as NSError
        return "\(swiftError.domain).\(error):\(swiftError.code)"
    }

    private static func send(_ name: String, _ properties: [String: AnalyticsValue]) {
        if let sendOverride {
            sendOverride(name, properties)
            return
        }
        mixpanel.track(event: name, properties: properties)
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

    /// Adds the ticker symbol beside each mint in properties keyed by their Mixpanel
    /// names, under the same rules as the `Property`-keyed variant.
    static func withTokenSymbols(
        _ properties: [String: AnalyticsValue],
        resolve: (String) -> String?
    ) -> [String: AnalyticsValue] {
        var enriched = properties
        for pair in mintProperties {
            guard let base58 = properties[pair.mint.rawValue] as? String,
                  let symbol = resolve(base58) else { continue }
            enriched[pair.symbol.rawValue] = symbol
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
            
            // Exported logs — same identifier, so a log file and a Bugsnag report never disagree
            LogStore.shared.userID = userID
            
            // Mixpanel
            mixpanel.identify(distinctId: userID)
            mixpanel.people.set(property: "$email", to: "userID:\(userID)")
        }
    }
}

// MARK: - People counters -

extension Analytics {
    /// Cumulative per-user counters, stored as Mixpanel *people* properties.
    ///
    /// A people property carries no event identity and cannot be decremented, so a
    /// replayed increment inflates the profile permanently and unattributably. Every
    /// caller must therefore sit behind a watermark — see `ConversationReceiptReporter`.
    typealias ReceivedCounter = PeopleCounter

    static func increment(_ counter: ReceivedCounter, by amount: Double = 1) {
        if let incrementOverride {
            incrementOverride(counter.key, amount)
            return
        }
        guard isEnabled else { return }
        mixpanel.people.increment(property: counter.key, by: amount)
    }
}

// MARK: - Private -

private extension Analytics {
    static var mixpanel: MixpanelInstance {
        Mixpanel.mainInstance()
    }
}
