//
//  Analytics.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import Mixpanel
import Bugsnag
import Firebase
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
    
    static func initialize() {
        FirebaseApp.app()?.isDataCollectionDefaultEnabled = true
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        let apiKey = try? InfoPlist.value(for: "mixpanel").value(for: "apiKey").string()
        if let apiKey {
            Mixpanel.initialize(token: apiKey, trackAutomaticEvents: true)
            logger.info("Initializing Mixpanel...")
        } else {
            logger.error("Failed to initialize Mixpanel. No API key found in Info.plist")
        }
    }
    
    static func track(event: some AnalyticsEvent, properties: [Property: AnalyticsValue]? = nil, error: Error? = nil) {
        var container: [String: AnalyticsValue] = [:]

        properties?.forEach { key, value in
            container[key.rawValue] = value
        }

        if let error {
            let swiftError = error as NSError
            container["Error"] = "\(swiftError.domain).\(error):\(swiftError.code)"
        }

        track(event.eventName, properties: container)
    }
    
//    static func track(_ action: Action, properties: [Property: AnalyticsValue]? = nil) {
//        var container: [String: AnalyticsValue] = [:]
//        
//        properties?.forEach { key, value in
//            container[key.rawValue] = value
//        }
//        
//        track(action.rawValue, properties: container)
//    }
    
    private static func track(_ name: String, properties: [String: AnalyticsValue]? = nil) {
        mixpanel.track(event: name, properties: properties)
    }
}

// MARK: - Identity -

extension Analytics {
    static func setIdentity(_ userID: UserID) {
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
