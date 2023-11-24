//
//  ErrorReporting.swift
//  Code
//
//  Created by Dima Bart on 2023-01-18.
//

import Foundation
import Bugsnag
import CodeServices

enum ErrorReporting {
    
    static func initialize() {
        Bugsnag.start()
    }
    
    static func breadcrumb(_ breadcrumb: Breadcrumb) {
        Bugsnag.leaveBreadcrumb(withMessage: breadcrumb.rawValue)
    }
    
    static func capturePayment(error: Swift.Error, rendezvous: PublicKey, tray: Tray, amount: KinAmount, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { userInfo in
            userInfo["rendezvous"] = rendezvous.base58
            userInfo["tray"]   = tray.reportableRepresentation()
            userInfo["amount"] = [
                "kin": amount.kin.description,
                "fx": amount.rate.fx.formatted(),
                "fiat": amount.kin.formattedFiat(rate: amount.rate, suffix: nil),
            ]
        }
    }
    
    static func captureMigration(error: Swift.Error,  tray: Tray, amount: Kin, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { userInfo in
            userInfo["tray"] = tray.reportableRepresentation()
            userInfo["kin"] = amount.description
        }
    }
    
    static func captureError(_ error: Swift.Error, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { _ in }
    }
    
    private static func capture(_ error: Swift.Error, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line, buildUserInfo: (inout [String: Any]) -> Void) {
        let swiftError = error as NSError
        
        var userInfo: [String: Any] = [:]
        
        swiftError.userInfo.forEach { key, value in
            userInfo[key] = value
        }
        
        let fileName = file.components(separatedBy: "/").last ?? "unknown"
        userInfo["location"] = "\(fileName):\(line)"
        
        buildUserInfo(&userInfo)
        
        if let reason {
            userInfo[NSLocalizedFailureReasonErrorKey] = reason
        }
        
        let customError = Fault(
            domain: "\(swiftError.domain).\(error)",
            code: swiftError.code,
            userInfo: userInfo
        )
        
        Bugsnag.notifyError(customError)
    }
}

class Fault: NSError {}

enum Breadcrumb: String {
    case permissionScreen = "Permission Screen"
    case verifyPhoneScreen = "Verify Phone Screen"
    case inviteCodeScreen = "Invite Code Screen"
    case confirmPhoneScreen = "Confirm Phone Screen"
    case regionSelectionScreen = "Region Selection Screen"
    case loginScreen = "Login Screen"
    case migrationScreen = "Migration Screen"
    case accountSelectionScreen = "Account Selection Screen"
    case contactsScreen = "Contacts Screen"
    case giveKinScreen = "Give Kin Screen"
    case balanceScreen = "Balance Screen"
    case bucketScreen = "Bucket Screen"
    case currencyScreen = "Currency Screen"
    case faqScreen = "FAQ Screen"
    case settingsScreen = "Settings Screen"
    case depositScreen = "Deposit Screen"
    case withdrawAmountScreen = "Withdraw Amount Screen"
    case withdrawAddressScreen = "Withdraw Address Screen"
    case withdrawSummaryScreen = "Withdraw Summary Screen"
    case backupScreen = "Backup Screen"
    case restrictedScreen = "Restricted Screen"
    case linkPhoneScreen = "Link Phone Screen"
    case deleteAccountScreen = "Delete Account Screen"
    case confirmDeleteScreen = "Confirm Delete Screen"
    case forceUpgradeScreen = "Force Upgrade Screen"
    case debugScreen = "Debug Screen"
    case getKinScreen = "Get Kin Screen"
    case getFriendStartedScreen = "Get Friend Started Screen"
    case remoteSendShareSheet = "Remote Send Share Sheet"
    case getFriendOnCodeShareSheet = "Get Friend on Code Share Sheet"
    case buyVideoScreen = "Buy Video Screen"
}
