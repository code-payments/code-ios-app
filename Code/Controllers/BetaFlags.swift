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
    
    @SecureString(.debugOptions) private var storedAccessGranted: String?
    
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
        
        case useBiometrics
        case vibrateOnScan
        case showConnectivityStatus
        case bucketDebugger
        case giveRequests
        case buyKin
        
        var id: String {
            localizedTitle
        }
        
        var localizedTitle: String {
            switch self {
            case .useBiometrics:
                return "Use Biometrics"
            case .vibrateOnScan:
                return "Vibrate on Scan"
            case .bucketDebugger:
                return "Bucket Debugger"
            case .showConnectivityStatus:
                return "Show Connectivity Status"
            case .giveRequests:
                return "Give Requests (Mode)"
            case .buyKin:
                return "Buy Kin"
            }
        }
        
        var localizedDescription: String {
            switch self {
            case .useBiometrics:
                return "If enabled, you'll have the ability to setup Face ID or Touch ID for additional security when giving Kin and more."
            case .vibrateOnScan:
                return "If enabled, the device will vibrate once to indicate that the camera has registered the code on the bill."
            case .bucketDebugger:
                return "If enabled, you'll gain the ability to tap the balance on the Balance screen to inspect individual bucket balances."
            case .showConnectivityStatus:
                return "If enabled, a 'No Connection' badge will be shown on the scan screen when no internet connection is detected."
            case .giveRequests:
                return "If enabled, Give Kin screen will show requests for entered amounts instead of cash bills."
            case .buyKin:
                return "If enabled, a Buy More Kin will appear in the balance screen."
            }
        }
    }
}

extension BetaFlags {
    static let mock = BetaFlags()
}
