//
//  IntroViewModel.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-10-23.
//

import SwiftUI
import CodeUI
import FlipchatServices

@MainActor
class IntroViewModel: ObservableObject {
    
    @Published var navigationPath: [NavPath] = []
    
    @Published var accountCreationState: ButtonState = .normal
    
    private let sessionAuthenticator: SessionAuthenticator
    private let banners: Banners
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, banners: Banners) {
        self.sessionAuthenticator = sessionAuthenticator
        self.banners = banners
    }
    
    // MARK: - Actions -
    
    func startLogin() {
        navigationPath.append(.login)
    }
    
    func startCreateAccount() {
        Task {
            accountCreationState = .loading
            
            let mnemonic: MnemonicPhrase = .generate(.words12)
            let initializedAccount = try await sessionAuthenticator.initialize(
                using: mnemonic,
                name: nil,
                isRegistration: true
            )
            
            try await Task.delay(milliseconds: 500)
            accountCreationState = .success
            try await Task.delay(milliseconds: 500)
            
            sessionAuthenticator.completeLogin(with: initializedAccount)
            
            try await Task.delay(milliseconds: 500)
            accountCreationState = .normal
        }
    }
}

extension IntroViewModel {
    enum NavPath {
        case login
    }
}
