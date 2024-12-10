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
    
    @Published var accessKeyButtonState: ButtonState = .normal
    
    @Published var accountCreationState: ButtonState = .normal
    
    @Published var inflightMnemonic: MnemonicPhrase
    
    var ownerForMnemonic: KeyPair {
        inflightMnemonic.solanaKeyPair()
    }
    
    var isEnteredNameValid: Bool {
        let count = enteredName.count
        return count >= 3 && count <= 26
    }
    
    private let sessionAuthenticator: SessionAuthenticator
    private let banners: Banners
    
    private var initializedAccount: InitializedAccount?
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator, banners: Banners) {
        self.sessionAuthenticator = sessionAuthenticator
        self.banners = banners
        self.inflightMnemonic = .generate(.words12)
    }
    
    func generateNewSeed() {
        inflightMnemonic = .generate(.words12)
    }
    
    // MARK: - Actions -
    
    func getStarted() {
        enteredName = ""
        navigationPath.append(.enterName)
    }
    
//    func completeLogin() {
//        guard let initializedAccount else {
//            return
//        }
//        
//        sessionAuthenticator.completeLogin(with: initializedAccount)
//    }
    
    func proceedWithEnteredName() {
        guard isEnteredNameValid else {
            showInvalidNameError()
            return
        }
        
        navigationPath.append(.accessKey)
    }
    
    // MARK: - Access Key -
    
    func promptSaveToPhotos() {
        Task {
            accessKeyButtonState = .loading
            
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: inflightMnemonic)
                
                try await Task.delay(milliseconds: 150)
                accessKeyButtonState = .success
                try await Task.delay(milliseconds: 400)
                
                navigationPath.append(.finalizeCreation)
                
                try await Task.delay(milliseconds: 500)
                accessKeyButtonState = .normal
                
            } catch {
                accessKeyButtonState = .normal
                banners.show(
                    style: .error,
                    title: "Failed to Save",
                    description: "Please allow Flipchat access to Photos in Settings in order to save your Access Key.",
                    actions: [
                        .cancel(title: Localized.Action.ok),
                        .standard(title: Localized.Action.openSettings) {
                            URL.openSettings()
                        }
                    ]
                )
            }
        }
    }
    
    func promptWrittenConfirmation() {
        banners.show(
            style: .error,
            title: "Are You Sure?",
            description: "These 12 words are the only way to recover your Code account. Make sure you wrote them down, and keep them private and safe.",
            position: .bottom,
            actions: [
                .destructive(title: "Yes, I Wrote Them Down") { [weak self] in
                    self?.navigationPath.append(.finalizeCreation)
                },
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
    
//    func registerEnteredName() {
//        Task {
//            guard isEnteredNameValid else {
//                throw GenericError(message: "Invalid name")
//            }
//            
//            accountCreationState = .loading
//            
//            let mnemonic: MnemonicPhrase = .generate(.words12)
//            inflightMnemonic = mnemonic
//            initializedAccount = try await sessionAuthenticator.initialize(using: mnemonic, name: enteredName, isRegistration: true)
//            
//            try await Task.delay(milliseconds: 500)
//            accountCreationState = .success
//            try await Task.delay(milliseconds: 500)
//            
//            navigationPath.append(.accessKey)
//            
//            try await Task.delay(milliseconds: 500)
//            accountCreationState = .normal
//        }
//    }
    
    // MARK: - Errors -
    
    func showInvalidNameError() {
        banners.show(
            style: .error,
            title: "Invalid Username",
            description: "Please enter a different username.",
            actions: [
                .cancel(title: "OK"),
            ]
        )
    }
}

extension OnboardingViewModel {
    enum NavPath {
        case enterName
        case accessKey
        case finalizeCreation
    }
}
