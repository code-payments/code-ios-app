//
//  Environment.swift
//  Code
//
//  Created by Dima Bart on 2021-04-07.
//

import Foundation

enum Environment {
    case dev
    case prod
}

extension Environment {
    
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

// MARK: - Kin -

extension Environment {
    var network: Network {
        switch self {
        case .dev:
            return .mainNet//.testNet
        case .prod:
            return .mainNet
        }
    }
}

// MARK: - ASCII -

extension Environment {
    var asciiDescription: String {
        switch self {
        case .dev:
            return """
              ██████  ███████ ██    ██
              ██   ██ ██      ██    ██
              ██   ██ █████   ██    ██
              ██   ██ ██       ██  ██
              ██████  ███████   ████
            """
        case .prod:
            return """
              ██████  ██████   ██████  ██████
              ██   ██ ██   ██ ██    ██ ██   ██
              ██████  ██████  ██    ██ ██   ██
              ██      ██   ██ ██    ██ ██   ██
              ██      ██   ██  ██████  ██████
            """
        }

    }
}

// MARK: - Current -

extension Environment {
    #if CODEDEV
    static let current: Environment = .dev
    #else
    static let current: Environment = .prod
    #endif
}
