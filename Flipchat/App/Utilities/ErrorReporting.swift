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
        Bugsnag.leaveBreadcrumb(
            breadcrumb.rawValue,
            metadata: nil,
            type: .navigation
        )
    }
    
    enum BreadcrumbType {
        case user
        case process
        case request
        
        var value: BSGBreadcrumbType {
            switch self {
            case .user:    return .user
            case .process: return .process
            case .request: return .request
            }
        }
    }
    
    static func breadcrumb(name: String, metadata: [String: Any] = [:], amount: KinAmount? = nil, kin: Kin? = nil, type: BreadcrumbType) {
        var container: [String: Any] = [:]
        
        metadata.forEach { key, value in
            container[key] = value
        }
        
        if let amount {
            container["amount"] = amount.descriptionDictionary
        }
        
        if let kin {
            container["kin"] = kin.description
        }
        
        Bugsnag.leaveBreadcrumb(
            name,
            metadata: container,
            type: type.value
        )
    }
    
    static func capturePayment(error: Swift.Error, rendezvous: PublicKey, tray: Tray, amount: KinAmount, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { userInfo in
            userInfo["rendezvous"] = rendezvous.base58
            userInfo["tray"]   = tray.reportableRepresentation()
            userInfo["amount"] = amount.descriptionDictionary
        }
    }
    
    static func captureMigration(error: Swift.Error,  tray: Tray, amount: Kin, reason: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, file: file, function: function, line: line) { userInfo in
            userInfo["tray"] = tray.reportableRepresentation()
            userInfo["kin"] = amount.description
        }
    }
    
    static func captureError(_ error: Swift.Error, reason: String? = nil, id: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        capture(error, reason: reason, id: id, file: file, function: function, line: line) { _ in }
    }
    
    private static func capture(_ error: Swift.Error, reason: String? = nil, id: String? = nil, file: String = #file, function: String = #function, line: Int = #line, buildUserInfo: (inout [String: Any]) -> Void) {
        let swiftError = error as NSError
        
        var userInfo: [String: Any] = [:]
        
        swiftError.userInfo.forEach { key, value in
            userInfo[key] = value
        }
        
        let fileName = file.components(separatedBy: "/").last ?? "unknown"
        let location = "\(fileName):\(function):\(line)"
        userInfo["location"] = location
        
        buildUserInfo(&userInfo)
        
        if let reason {
            userInfo[NSLocalizedFailureReasonErrorKey] = reason
        }
        
        let customError = Fault(
            domain: "\(swiftError.domain).\(error)",
            code: swiftError.code,
            userInfo: userInfo
        )
        
        Bugsnag.notifyError(customError) { event in
            if !event.errors.isEmpty {
                event.errors[0].errorClass = "\(error)"
                event.errors[0].errorMessage = reason ?? ""
            }
            
            // Skip the line numbers to maintain grouping
            // even when files and line numbers change.
            var hash = "\(fileName):\(function)"
            if let id {
                hash = "\(hash):\(id)"
            }
            event.groupingHash = hash
            
            return true
        }
    }
}

class Fault: NSError, @unchecked Sendable {}

enum Breadcrumb: String {
    case migrationScreen = "Migration Screen"
    case restrictedScreen = "Restricted Screen"
    case accountSelectionScreen = "Account Selection Screen"
}
