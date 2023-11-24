//
//  Biometrics.swift
//  Code
//
//  Created by Dima Bart on 2022-09-10.
//

import Foundation
import LocalAuthentication
import CodeServices

@MainActor
class Biometrics: ObservableObject {

    @Published private(set) var isAvailable: Bool = false
    
    @Published private(set) var isEnabled: Bool = false
    
    @Published private(set) var kind: Kind = .none
    
    private let policy: LAPolicy = .deviceOwnerAuthentication
    
    @Defaults(.biometricsEnabled) private var storedEnabled: Bool?
    
    // MARK: - Init -
    
    init() {
        loadAvailableState()
        loadEnabledState()
    }
    
    private func loadAvailableState() {
        do {
            let context = Context(policy: policy)
            try context.canEvaluate()
            isAvailable = true
            kind = context.kind
        } catch {
            isAvailable = false
            kind = .none
        }
    }
    
    private func loadEnabledState() {
        isEnabled = storedEnabled ?? false
    }
    
    // MARK: - Enable -
    
    func setEnabledAndVerify(_ enabled: Bool) {
        isEnabled = enabled
        Task {
            let context  = Context(policy: policy)
            let verified = await context.verify(reason: enabled ? .enable : .disable)
            if verified {
                storedEnabled = enabled
            } else {
                isEnabled = !enabled
            }
        }
    }
    
    // MARK: - Actions -
    
    func verificationContext() -> Context? {
        guard isEnabled else {
            return nil
        }
        
        return Context(policy: policy)
    }
}

// MARK: - Kind -

extension Biometrics {
    enum Kind {
        case none
        case touchID
        case faceID
    }
}

// MARK: - Context -

extension Biometrics {
    class Context {
            
        let policy: LAPolicy
        
        var kind: Biometrics.Kind {
            switch context.biometryType {
            case .none:    return .none
            case .touchID: return .touchID
            case .faceID:  return .faceID
            case .opticID: return .faceID
            @unknown default:
                return .none
            }
        }
        
        private let context = LAContext()

        init(policy: LAPolicy) {
            self.policy = policy
        }
        
        func canEvaluate() throws {
            var error: NSError?
            context.canEvaluatePolicy(policy, error: &error)
            
            if let error = error {
                trace(.failure, components: "Biometrics not available: \(error)")
                throw error
            }
        }
        
        func verify(reason: Reason) async -> Bool {
            do {
                try await context.evaluatePolicy(policy, localizedReason: reason.description)
                return true
            } catch {
                trace(.failure, components: "Biometrics failed authentication: \(error)")
                return false
            }
        }
    }
}

// MARK: - Context.Reason -

extension Biometrics.Context {
    enum Reason {
        
        case enable
        case disable
        case access
        case giveKin
        case withdraw
        
        var description: String {
            switch self {
            case .enable:   return Localized.Subtitle.enableFaceID
            case .disable:  return Localized.Subtitle.disableFaceID
            case .access:   return Localized.Subtitle.accessKeyFaceID
            case .giveKin:  return Localized.Subtitle.giveKinFaceID
            case .withdraw: return Localized.Subtitle.withdrawKinFaceID
            }
        }
    }
}

extension Biometrics {
    static let mock = Biometrics()
}
