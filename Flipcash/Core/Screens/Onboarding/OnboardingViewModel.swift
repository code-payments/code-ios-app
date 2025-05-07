//
//  OnboardingViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class OnboardingViewModel: ObservableObject {
    
    @Published var path: [OnboardingPath] = []
    
    @Published var accessKeyButtonState: ButtonState = .normal
    
    @Published var dialogItem: DialogItem?
    
    private(set) var inflightMnemonic: MnemonicPhrase = .generate(.words12)
    
    private let container: Container
    
    // MARK: - Init -
    
    init(container: Container) {
        self.container = container
    }
    
    // MARK: - Action -
    
    func loginAction() {
        navigateToLogin()
    }
    
    func createAccountAction() {
        inflightMnemonic = MnemonicPhrase.generate(.words12)
        navigateToAccessKey()
//        Task {
//            loginButtonState = .loading
//            defer {
//                loginButtonState = .normal
//            }
//            let account  = try await initialize(
//                using: mnemonic,
//                isRegistration: true
//            )
//            
//            // Prevent server race condition for airdrop
//            try await Task.delay(seconds: 1)
//            
//            _ = try await client.airdrop(
//                type: .getFirstCrypto,
//                owner: account.keyAccount.derivedKey.keyPair
//            )
//            
//            completeLogin(with: account)
//        }
    }
    
    func saveToPhotosAction() {
        Task {
            accessKeyButtonState = .loading
            
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: inflightMnemonic)
                
                try await Task.delay(milliseconds: 150)
                accessKeyButtonState = .success
                try await Task.delay(milliseconds: 400)
                
                navigateToPurchaseScreen()
                
                try await Task.delay(milliseconds: 500)
                accessKeyButtonState = .normal
                
            } catch {
                accessKeyButtonState = .normal
                // TODO: Show error
//                banners.show(
//                    style: .error,
//                    title: "Failed to Save",
//                    description: "Please allow Flipchat access to Photos in Settings in order to save your Access Key.",
//                    actions: [
//                        .cancel(title: Localized.Action.ok),
//                        .standard(title: Localized.Action.openSettings) {
//                            URL.openSettings()
//                        }
//                    ]
//                )
            }
        }
    }
    
    func wroteDownAction() {
        dialogItem = .init(
            style: .destructive,
            title: "Are You Sure?",
            subtitle: "These 12 words are the only way to recover your Flipcash account. Make sure you wrote them down, and keep them private and safe.",
            dismissable: true
        ) {
            .destructive("Yes, I Wrote Them Down") {
                
            };
            .cancel {}
        }
    }
    
    // MARK: - Navigation -
    
    func navigateToLogin() {
        path = [.login]
    }
    
    func navigateToAccessKey() {
        path = [.accessKey]
    }
    
    func navigateToPurchaseScreen() {
        
    }
}

// MARK: - Path -

enum OnboardingPath {
    case login
    case accessKey
    case purchase
}
