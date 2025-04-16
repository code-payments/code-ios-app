//
//  Env.swift
//  Code
//
//  Created by Dima Bart on 2021-04-07.
//

import Foundation

enum Env {}

extension Env {
    
    enum Variable: String {
        case mixpanel      = "MIXPANEL"
        case bugsnag       = "BUGSNAG"
    }
    
    static func variable(_ variable: Variable) -> String? {
        let value = ProcessInfo.processInfo.environment[variable.rawValue]
        
        if let value = value, value.isEmpty {
            // Don't return empty strings
            return nil
        }
        
        return value
    }
}
