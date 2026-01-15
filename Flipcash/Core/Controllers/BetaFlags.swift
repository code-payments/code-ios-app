//
//  BetaFlags.swift
//  Code
//
//  Created by Dima Bart on 2021-03-25.
//

import Foundation
import SwiftUI

class BetaFlags: ObservableObject {
    
    static let shared = BetaFlags()
    
    @Published private(set) var options: Set<Option> = []
    
    @Published private(set) var accessGranted: Bool = false
    
    @Defaults(.betaFlags) private var storedOptions: Set<Option>?
    
    @SecureString(.betaFlagsEnabled) private var storedAccessGranted: String?
    
    // MARK: - Init -
    
    private init() {
        readStoredOptions()
        readAccessGranted()
    }
    
    func hasEnabled(_ option: Option) -> Bool {
        options.contains(option)
    }
    
    func set(_ option: Option, enabled: Bool) {
        if enabled {
            options.insert(option)
        } else {
            options.remove(option)
        }
        writeToCache()
    }
    
    func setAccessGranted(_ granted: Bool) {
        if granted {
            storedAccessGranted = "granted"
        } else {
            storedAccessGranted = nil
        }
        accessGranted = granted
    }
    
    func bindingFor(option: Option) -> Binding<Bool> {
        Binding { [weak self] in
            self?.options.contains(option) ?? false
            
        } set: { [weak self] enabled in
            self?.set(option, enabled: enabled)
        }
    }
    
    // MARK: - Cache -
    
    private func writeToCache() {
        self.storedOptions = options
    }
    
    private func readAccessGranted() {
        if let _ = storedAccessGranted {
            accessGranted = true
        } else {
            accessGranted = false
        }
    }
    
    private func readStoredOptions() {
        if let options = storedOptions {
            self.options = options
        }
    }
}

// MARK: - Option -

extension BetaFlags {
    enum Option: String, Hashable, Equatable, Codable, CaseIterable, Identifiable {

        case transactionDetails
        case vibrateOnScan
        case enableCoinbase
        case coinbaseSandbox
        
        var id: String {
            localizedTitle
        }
        
        var localizedTitle: String {
            switch self {
            case .transactionDetails:
                return "Transaction details"
            case .vibrateOnScan:
                return "Vibrate on scan"
            case .enableCoinbase:
                return "Enable Coinbase"
            case .coinbaseSandbox:
                return "Coinbase Sandbox"
            }
        }
        
        var localizedDescription: String {
            switch self {
            case .transactionDetails:
                return "If enabled, tapping a transaction in Balance will open a details modal"
            case .vibrateOnScan:
                return "If enabled, the device will vibrate to indicate that the camera has registered the code on the bill"
            case .enableCoinbase:
                return "If enabled, Coinbase onramp will be available regardless of region"
            case .coinbaseSandbox:
                return "If enabled, all Coinbase transactions will go through the sandbox environment"
            }
        }
    }
}

extension BetaFlags {
    static let mock = BetaFlags()
}
