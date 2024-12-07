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
            let mnemonic: MnemonicPhrase = .generate(.words12)
            let initializedAccount = try await sessionAuthenticator.initialize(
                using: mnemonic,
                name: nil,
                isRegistration: true
            )
            sessionAuthenticator.completeLogin(with: initializedAccount)
        }
    }
}

extension IntroViewModel {
    enum NavPath {
        case login
    }
}
