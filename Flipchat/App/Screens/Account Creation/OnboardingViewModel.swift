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
    
    @Published var paymentButtonState: ButtonState = .normal
    
    @Published var createAccountCost: String?
    
    var mnemonic: MnemonicPhrase {
        session.organizer.mnemonic
    }
    
    var owner: KeyPair {
        session.organizer.ownerKeyPair
    }
    
    var isEnteredNameValid: Bool {
        let count = enteredName.count
        return count >= 3 && count <= 26
    }
    
    let storeController: StoreController
    
    private let session: Session
    private let chatController: ChatController
    private let chatViewModel: ChatViewModel
    
    private let client: Client
    private let flipClient: FlipchatClient
    private let banners: Banners
    
    private let isPresenting: Binding<Bool>
    private let completion: () async throws -> Void
    
    // MARK: - Init -
    
    init(state: AuthenticatedState, container: AppContainer, isPresenting: Binding<Bool>, completion: @escaping () async throws -> Void) {
        self.session         = state.session
        self.chatController  = state.chatController
        self.chatViewModel   = state.chatViewModel
        self.storeController = state.storeController
        
        self.client          = container.client
        self.flipClient      = container.flipClient
        self.banners         = container.banners
        
        self.isPresenting    = isPresenting
        self.completion      = completion
    }
    
    // MARK: - Actions -
    
    func getStarted() {
        enteredName = ""
        navigationPath.append(.enterName)
    }
    
    func proceedWithEnteredName() {
        guard isEnteredNameValid else {
            showInvalidNameError()
            return
        }
        
        navigationPath.append(.accessKey)
    }
    
    func dismiss() {
        isPresenting.wrappedValue = false
    }
    
    private func setPaymentState(_ state: ButtonState) {
        paymentButtonState = state
    }
    
    // MARK: - In-App Purchases -
    
    func payForCreateAccount() async throws {
        setPaymentState(.loading)
        
        do {
            let result = try await storeController.pay(for: .createAccount)
            switch result {
            case .success(let purchasedProduct):
                
                if purchasedProduct == .createAccount {
                    try await completeAccountUpgrade()
                    setPaymentState(.success)
                    Task {
                        try await Task.delay(milliseconds: 200)
                        dismiss()
                        try await Task.delay(milliseconds: 200)
                        try await completion()
                    }
                }
                
            case .failed:
                showPurchaseFailed()
                setPaymentState(.normal)
                
            case .cancelled:
                setPaymentState(.normal)
            }
            
        } catch {
            setPaymentState(.normal)
            showPurchaseUnavailable()
            ErrorReporting.captureError(error)
        }
    }
    
    private func completeAccountUpgrade() async throws {
        // 1. Open all required VM accounts
        try await client.createAccounts(with: session.organizer)
        
        // 2. Update account from anonymous to a named one
        try await flipClient.setDisplayName(name: enteredName, owner: owner)
        
        // 3. Airdrop initial account Kin balance
        _ = try? await client.airdrop(type: .getFirstKin, owner: owner)
        
        // 4. Update the user's balance to reflect
        // the aidropped Kin right away
        _ = try await session.updateBalance()
        
        // 5. Update the user flags to indicate that
        // this account is now registered
        _ = try await session.updateUserFlags()
    }
    
    // MARK: - Access Key -
    
    func promptSaveToPhotos() {
        Task {
            accessKeyButtonState = .loading
            
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: session.organizer.mnemonic)
                
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
    
    func showPurchaseUnavailable() {
        banners.show(
            style: .error,
            title: "Purchase Unavailable",
            description: "Please check your internet connection and try again.",
            actions: [
                .cancel(title: "OK"),
            ]
        )
    }
    
    func showPurchaseFailed() {
        banners.show(
            style: .error,
            title: "Purchase Failed",
            description: "Something went wrong during payment. Please try again.",
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

extension OnboardingViewModel {
    struct JoinRoom {
        let chatID: ChatID
        let hostID: UserID
        let cover: Kin
    }
}
