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

protocol AnalyticsEvent {
    var eventName: String { get }
}

extension AnalyticsEvent where Self: RawRepresentable<String> {
    var eventName: String { rawValue }
}

enum Analytics {

    private static var isEnabled = false

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

        properties?.forEach { key, value in
            container[key.rawValue] = value
        }

        if let error {
            let swiftError = error as NSError
            container["Error"] = "\(swiftError.domain).\(error):\(swiftError.code)"
        }

        mixpanel.track(event: event.eventName, properties: container)
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
