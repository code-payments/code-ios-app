//
//  BetaFlags.swift
//  Code
//
//  Created by Dima Bart on 2021-03-25.
//

import Foundation
import SwiftUI

//class BetaFlags: ObservableObject {
//    
//    static let shared = BetaFlags()
//    
//    @Published private(set) var options: Set<Option> = []
//    
//    @Published private(set) var accessGranted: Bool = false
//    
//    @Defaults(.betaFlags) private var storedOptions: Set<Option>?
//    
//    @SecureString(.betaEnabled) private var storedAccessGranted: String?
//    
//    // MARK: - Init -
//    
//    private init() {
//        readStoredOptions()
//        readAccessGranted()
//    }
//    
//    func hasEnabled(_ option: Option) -> Bool {
//        options.contains(option)
//    }
//    
//    func set(_ option: Option, enabled: Bool) {
//        if enabled {
//            options.insert(option)
//        } else {
//            options.remove(option)
//        }
//        writeToCache()
//    }
//    
//    func setAccessGranted(_ granted: Bool) {
//        if granted {
//            storedAccessGranted = "granted"
//        } else {
//            storedAccessGranted = nil
//        }
//        accessGranted = granted
//    }
//    
//    func bindingFor(option: Option) -> Binding<Bool> {
//        Binding { [weak self] in
//            self?.options.contains(option) ?? false
//            
//        } set: { [weak self] enabled in
//            self?.set(option, enabled: enabled)
//        }
//    }
//    
//    // MARK: - Cache -
//    
//    private func writeToCache() {
//        self.storedOptions = options
//    }
//    
//    private func readAccessGranted() {
//        if let _ = storedAccessGranted {
//            accessGranted = true
//        } else {
//            accessGranted = false
//        }
//    }
//    
//    private func readStoredOptions() {
//        if let options = storedOptions {
//            self.options = options
//        }
//    }
//}
//
//// MARK: - Option -
//
//extension BetaFlags {
//    enum Option: String, Hashable, Equatable, Codable, CaseIterable, Identifiable {
//        
//        case placeholder
//        
//        var id: String {
//            localizedTitle
//        }
//        
//        var localizedTitle: String {
//            switch self {
//            case .placeholder:
//                return "Temp"
//            }
//        }
//        
//        var localizedDescription: String {
//            switch self {
//            case .placeholder:
//                return "If enabled, this is a placeholder."
//            }
//        }
//    }
//}
//
//extension BetaFlags {
//    static let mock = BetaFlags()
//}
