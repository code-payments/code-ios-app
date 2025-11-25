//
//  Defaults.swift
//  Code
//
//  Created by Dima Bart on 2021-03-16.
//

import Foundation

enum DefaultsKey: String {
    
//    case entryCurrency      = "com.code.currency.inputCurrency"
//    case localCurrency      = "com.code.currency.localCurrency"
//    case recentCurrencies   = "com.code.currency.recentCurrencies"
//    case localCurrencyAdded = "com.code.currency.localCurrencyAdded"
    
//    case twitterUser    = "com.code.social.twitterUser"
//    case hasSeenTipCard = "com.code.social.hasSeenTipCard"
    
//    case wasPromptedPush = "com.code.state.wasPromptedForPush"
//    
//    case tooltipLogo = "com.code.tooltip.logo"
    
    // Settings
    
//    case biometricsEnabled = "com.code.biometrics.enabled"
    
    case wasLoggedIn = "com.flipcash.state.wasLoggedIn"
    case launchCount = "com.flipcash.state.launchCount"
    
    case cameraAutoStartDisabled = "com.flipcash.camera.autoStartDisabled"
    case cameraEnabledState      = "com.flipcash.camera.cameraEnabledState"
    
    case entryCurrency      = "com.flipcash.currency.entryCurrency"
    case balanceCurrency    = "com.flipcash.currency.balanceCurrency"
    case onrampCurrency     = "com.flipcash.currency.onrampCurrency"
    case recentCurrencies   = "com.flipcash.currency.recentCurrencies"
    case localCurrencyAdded = "com.flipcash.currency.localCurrencyAdded"
    
    case storedTokenMint = "com.flipcash.token.storedTokenMint"
    case storedTokenName = "com.flipcash.token.storedTokenName"
    case storedTokenImageURL = "com.flipcash.token.storedTokenImageURL"
    
    case betaFlags = "com.flipcash.betaFlags"
    
    case pendingPurchase = "com.flipcash.iap.pendingPurchase"
    
    // Legacy
    
//    case faqs = "com.code.faqs"
//    case inviteCount = "com.code.inviteCount"
//    case lastSeenInviteCount = "com.code.lastSeenInviteCount"
}

@propertyWrapper
struct Defaults<T> where T: Codable {
    
    var wrappedValue: T? {
        get {
            decode(UserDefaults.standard.data(forKey: key.rawValue))
        }
        set {
            if let newValue = encode(newValue) {
                UserDefaults.standard.setValue(newValue, forKey: key.rawValue)
            } else {
                UserDefaults.standard.removeObject(forKey: key.rawValue)
            }
        }
    }
    
    private let key: DefaultsKey
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Init -
    
    init(_ key: DefaultsKey) {
        self.key = key
    }
    
    // MARK: - Codable -
    
    private func encode(_ value: T?) -> Data? {
        guard let value = value else {
            return nil
        }
        
        return try? encoder.encode(value)
    }
    
    private func decode(_ data: Data?) -> T? {
        guard let data = data else {
            return nil
        }
        
        return try? decoder.decode(T.self, from: data)
    }
}
