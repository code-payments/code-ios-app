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
    
    @Published var buyAccountButtonState: ButtonState = .normal
    
    @Published var dialogItem: DialogItem?
    
    let storeController: StoreController
    
    private(set) var inflightMnemonic: MnemonicPhrase = .generate(.words12)
    
    private let container: Container
    private let client: Client
    private let sessionAuthenticator: SessionAuthenticator
    private let cameraAuthorizer: CameraAuthorizer
    
    private var initializedAccount: InitializedAccount?
    
    // MARK: - Init -
    
    init(container: Container) {
        self.container            = container
        self.client               = container.client
        self.sessionAuthenticator = container.sessionAuthenticator
        self.storeController      = container.storeController
        self.cameraAuthorizer     = CameraAuthorizer()
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
                
                navigateToBuyAccountScreen()
                
                try await Task.delay(milliseconds: 500)
                accessKeyButtonState = .normal
                
            } catch {
                accessKeyButtonState = .normal
                dialogItem = .init(
                    style: .destructive,
                    title: "Failed to Save",
                    subtitle: "Please allow Flipchat access to Photos in Settings in order to save your Access Key.",
                    dismissable: true
                ) {
                    .standard("Open Settings") {
                        URL.openSettings()
                    };
                    .notNow()
                }
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
            .destructive("Yes, I Wrote Them Down") { [weak self] in
                self?.navigateToBuyAccountScreen()
            };
            .cancel()
        }
    }
    
    func buyAccountAction() {
        buyAccountButtonState = .loading
        Task {
            do {
                let result = try await storeController.pay(
                    for: .createAccountWithWelcomeBonus,
                    owner: inflightMnemonic.solanaKeyPair()
                )
                
                switch result {
                case .success(let product):
                    
                    try await createAccount()
                    buyAccountButtonState = .success
                    try await Task.delay(seconds: 1)
                    navigationToCameraAccessScreen()
                    
                case .failed, .cancelled:
                    buyAccountButtonState = .normal
                }
                
            } catch {
                dialogItem = .init(
                    style: .destructive,
                    title: "Something Went Wrong",
                    subtitle: "We couldn't create your account. Please try again.",
                    dismissable: true
                ) {
                    .okay()
                }
                buyAccountButtonState = .normal
            }
        }
    }
    
    func allowCameraAccessAction() {
        cameraAuthorizer.authorize { [weak self] _ in
            // Regardless of authorization status
            // continue to finalize the account,
            // they'll have an opportunity to grant
            // access on the camera screen
            self?.completeOnboardingAndLogin()
        }
    }
    
    func skipCameraAccessAction() {
        completeOnboardingAndLogin()
    }
    
    // MARK: - Account Creation -
    
    private func createAccount() async throws {
        let account = try await sessionAuthenticator.initialize(
            using: inflightMnemonic,
            isRegistration: true
        )
        
        // Prevent server race condition for airdrop
        try await Task.delay(seconds: 1)
        
        try await client.airdrop(
            type: .getFirstCrypto,
            owner: account.keyAccount.derivedKey.keyPair
        )
        
        initializedAccount = account
    }
    
    private func completeOnboardingAndLogin() {
        guard let initializedAccount else {
            return
        }
        
        sessionAuthenticator.completeLogin(with: initializedAccount)
    }
    
    // MARK: - Navigation -
    
    func navigateToLogin() {
        path = [.login]
    }
    
    func navigateToAccessKey() {
        path = [.accessKey]
    }
    
    func navigateToBuyAccountScreen() {
        path.append(.buyAccount)
    }
    
    func navigationToCameraAccessScreen() {
        path.append(.cameraAccess)
    }
}

// MARK: - Path -

enum OnboardingPath {
    case login
    case accessKey
    case buyAccount
    case cameraAccess
}
