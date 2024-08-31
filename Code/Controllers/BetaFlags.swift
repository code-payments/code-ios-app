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
        
        case vibrateOnScan
        case showConnectivityStatus
        case bucketDebugger
        case giveRequests
        case canUnsubcribe
        case disableBuyModule
        case conversations
        case alternativeBubbles
        case kadoInApp
        case chatTab
        case reverseZoom
        
        var id: String {
            localizedTitle
        }
        
        var localizedTitle: String {
            switch self {
            case .vibrateOnScan:
                return "Vibrate on Scan"
            case .bucketDebugger:
                return "Bucket Debugger"
            case .showConnectivityStatus:
                return "Show Connectivity Status"
            case .giveRequests:
                return "Request Kin"
            case .canUnsubcribe:
                return "Can Unsubscribe"
            case .disableBuyModule:
                return "Disable Buy Module"
            case .conversations:
                return "Conversations"
            case .alternativeBubbles:
                return "Alternative Bubbles"
            case .kadoInApp:
                return "Kado In-app Flow"
            case .chatTab:
                return "Chat Tab"
            case .reverseZoom:
                return "Reverse Zoom"
            }
        }
        
        var localizedDescription: String {
            switch self {
            case .vibrateOnScan:
                return "If enabled, the device will vibrate once to indicate that the camera has registered the code on the bill."
            case .bucketDebugger:
                return "If enabled, you'll gain the ability to tap the balance on the Balance screen to inspect individual bucket balances."
            case .showConnectivityStatus:
                return "If enabled, a 'No Connection' badge will be shown on the scan screen when no internet connection is detected."
            case .giveRequests:
                return "If enabled, Request Kin screen will replace Get Kin."
            case .canUnsubcribe:
                return "If enabled, an option to unsubscribe from a chat will appear for supported chats."
            case .disableBuyModule:
                return "If enabled, the Buy Module will appear to be disabled."
            case .conversations:
                return "If enabled, an experimental conversation view will become available via the 'Mute' button."
            case .alternativeBubbles:
                return "If enabled, conversation view will use an alternative look to timestamps in payment bubbles."
            case .kadoInApp:
                return "If enabled, the Kado purchase experience will open in an in-app browser."
            case .chatTab:
                return "If enabled, a fourth chat tab will appear on the camera screen."
            case .reverseZoom:
                return "If enabled, gesture to zoom-in will become 'drag up' instead of 'drag down'."
            }
        }
    }
}

extension BetaFlags {
    static let mock = BetaFlags()
}
