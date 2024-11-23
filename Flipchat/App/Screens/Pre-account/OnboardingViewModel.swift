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
    
    @Published var inflightMnemonic: MnemonicPhrase? = nil
    
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
    }
    
    // MARK: - Actions -
    
    func startLogin() {
        navigationPath.append(.login)
    }
    
    func startCreateAccount() {
        navigationPath.append(.enterName)
    }
    
    func completeLogin() {
        guard let initializedAccount else {
            return
        }
        
        sessionAuthenticator.completeLogin(with: initializedAccount)
    }
    
    func authorizePushPermissions() async throws {
        try? await PushController.authorize()
        completeLogin()
    }
    
    private func requiresPushAuthorization() async -> Bool {
        await PushController.fetchStatus() == .notDetermined
    }
    
    func registerEnteredName() {
        Task {
            guard isEnteredNameValid else {
                throw GenericError(message: "Invalid name")
            }
            
            accountCreationState = .loading
            
            let mnemonic: MnemonicPhrase = .generate(.words12)
            inflightMnemonic = mnemonic
            initializedAccount = try await sessionAuthenticator.initialize(using: mnemonic, name: enteredName)
            
            try await Task.delay(milliseconds: 500)
            accountCreationState = .success
            try await Task.delay(milliseconds: 500)
            
            navigationPath.append(.accessKey)
            
            try await Task.delay(milliseconds: 500)
            accountCreationState = .normal
        }
    }
    
    // MARK: - Access Key -
    
    func promptSaveToPhotos() {
        guard let inflightMnemonic else {
            return
        }
        
        Task {
            accessKeyButtonState = .loading
            
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: inflightMnemonic)
                
                try await Task.delay(milliseconds: 150)
                accessKeyButtonState = .success
                try await Task.delay(milliseconds: 400)
                
                if await requiresPushAuthorization() {
                    navigationPath.append(.permissionPush)
                } else {
                    completeLogin()
                }
                
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
                    self?.navigationPath.append(.permissionPush)
                },
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
}

extension OnboardingViewModel {
    enum NavPath {
        case enterName
        case permissionPush
        case accessKey
        case login
    }
}
