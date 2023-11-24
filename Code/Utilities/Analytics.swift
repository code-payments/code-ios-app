//
//  Analytics.swift
//  Code
//
//  Created by Dima Bart on 2021-12-07.
//

import Foundation
import Mixpanel
import Firebase
import CodeServices
import Bugsnag

typealias AnalyticsValue = MixpanelType

enum Analytics {
    
    static func initialize() {
        FirebaseApp.app()?.isDataCollectionDefaultEnabled = true
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        if 
            let plist = Bundle.main.infoDictionary,
            let mixpanel = plist["mixpanel"] as? [String: String],
            let apiKey = mixpanel["apiKey"]
        {
            Mixpanel.initialize(token: apiKey)
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
    
    private static func track(_ name: String, properties: [String: AnalyticsValue]? = nil) {
        mixpanel.track(event: name, properties: properties)
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
            Bugsnag.setUser(userID, withEmail: user.phone?.e164, andName: nil)
            
            // Mixpanel
            mixpanel.identify(distinctId: userID)
            
            if let phone = user.phone?.e164 {
                mixpanel.people.set(property: "$email", to: phone)
            }
        }
    }
}

// MARK: - Private -

private extension Analytics {
    static var mixpanel: MixpanelInstance {
        Mixpanel.mainInstance()
    }
}
