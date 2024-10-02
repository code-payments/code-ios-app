//
//  Analytics.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import CodeServices
//import Mixpanel
//import Firebase
//import Bugsnag

typealias AnalyticsValue = Any//MixpanelType

enum Analytics {
    
    static func initialize() {
//        FirebaseApp.app()?.isDataCollectionDefaultEnabled = true
//        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        let apiKey = try? InfoPlist.value(for: "mixpanel").value(for: "apiKey").string()
        if let apiKey {
//            Mixpanel.initialize(token: apiKey, trackAutomaticEvents: true)
            trace(.success, components: "Initializing Mixpanel...")
        } else {
            trace(.failure, components: "Failed to initialize Mixpanel. No API key found in Info.plist")
        }
    }
    
    static func track(_ event: Name, properties: [Property: AnalyticsValue]? = nil, error: Error? = nil) {
        var container: [String: AnalyticsValue] = [:]
        
        properties?.forEach { key, value in
            container[key.rawValue] = value
        }
        
        if let error {
            let swiftError = error as NSError
            container["Error"] = "\(swiftError.domain).\(error):\(swiftError.code)"
        }
        
        track(event.rawValue, properties: container)
    }
    
    static func track(_ action: Action, properties: [Property: AnalyticsValue]? = nil) {
        var container: [String: AnalyticsValue] = [:]
        
        properties?.forEach { key, value in
            container[key.rawValue] = value
        }
        
        track(action.rawValue, properties: container)
    }
    
    private static func track(_ name: String, properties: [String: AnalyticsValue]? = nil) {
//        mixpanel.track(event: name, properties: properties)
    }
}

// MARK: - Identity -

extension Analytics {
    static func setIdentity(_ user: User) {
        // Ensure that this runs after `initialize` has been called
        // on all the tracking platforms
        DispatchQueue.main.async {
            let userID = user.id.uuid?.uuidString ?? user.id.data.hexEncodedString()
            
            // Bugsnag
//            Bugsnag.setUser(userID, withEmail: user.phone?.e164, andName: nil)
            
            // Mixpanel
//            mixpanel.identify(distinctId: userID)
//            
//            if let phone = user.phone?.e164 {
//                mixpanel.people.set(property: "$email", to: phone)
//            }
        }
    }
}

// MARK: - Private -

private extension Analytics {
//    static var mixpanel: MixpanelInstance {
//        Mixpanel.mainInstance()
//    }
}
