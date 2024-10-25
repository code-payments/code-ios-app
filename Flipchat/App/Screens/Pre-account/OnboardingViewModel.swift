//
//  OnboardingViewModel.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-10-23.
//

import SwiftUI
import CodeUI
import CodeServices
import FlipchatServices

@MainActor
class OnboardingViewModel: ObservableObject {
    
    @Published var navigationPath: [NavPath] = []
    
    @Published var enteredName: String = ""
    
    @Published var accountCreationState: ButtonState = .normal
    
    var isEnteredNameValid: Bool {
        let count = enteredName.count
        return count >= 3 && count <= 12
    }
    
    private let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.sessionAuthenticator = sessionAuthenticator
    }
    
    // MARK: - Account -
    
    private func registerAccount(name: String) async throws {
        guard isEnteredNameValid else {
            throw GenericError(message: "Invalid name")
        }
        
        sessionAuthenticator.completeLogin(
            with: try await sessionAuthenticator.initializeNewAccount(name: name)
        )
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
            accountCreationState = .loading
            try await registerAccount(name: enteredName)
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
