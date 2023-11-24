//
//  Environment.swift
//  Code
//
//  Created by Dima Bart on 2021-04-07.
//

import Foundation
import CodeServices

enum Environment {
    case dev
    case prod
}

// MARK: - Kin -

extension Environment {
    var network: Network {
        switch self {
        case .dev:
            return .testNet
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
