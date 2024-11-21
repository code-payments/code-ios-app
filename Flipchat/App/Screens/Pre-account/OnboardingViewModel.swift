//
//  OnboardingViewModel.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-10-23.
//

import SwiftUI
import CodeUI
import FlipchatServices

@MainActor
class OnboardingViewModel: ObservableObject {
    
    @Published var navigationPath: [NavPath] = []
    
    @Published var enteredName: String = ""
    
    @Published var accountCreationState: ButtonState = .normal
    
    var isEnteredNameValid: Bool {
        let count = enteredName.count
        return count >= 3 && count <= 26
    }
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Actions -
    
    func startLogin() {
        navigationPath.append(.login)
    }
    
    func startCreateAccount() {
        navigationPath.append(.enterName)
    }
    
    func registerEnteredName() {
        Task {
            do {
                guard isEnteredNameValid else {
                    throw GenericError(message: "Invalid name")
                }
                
                accountCreationState = .loading
                let initializedAccount = try await sessionAuthenticator.initializeNewAccount(name: enteredName)
                
                try await Task.delay(milliseconds: 500)
                accountCreationState = .success
                
                try await Task.delay(milliseconds: 500)
                sessionAuthenticator.completeLogin(with: initializedAccount)
                
                try await Task.delay(milliseconds: 500)
                accountCreationState = .normal
                
            } catch {
                accountCreationState = .normal
            }
        }
    }
}

extension OnboardingViewModel {
    enum NavPath {
        case enterName
        case permissionPush
        case login
    }
}
