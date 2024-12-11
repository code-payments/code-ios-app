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
    
    private let session: Session
    private let client: Client
    private let flipClient: FlipchatClient
    private let banners: Banners
    private let isPresenting: Binding<Bool>
    
    private lazy var storeController = StoreController(delegate: self)
    
    // MARK: - Init -
    
    init(session: Session, client: Client, flipClient: FlipchatClient, banners: Banners, isPresenting: Binding<Bool>) {
        self.session = session
        self.banners = banners
        self.client = client
        self.flipClient = flipClient
        self.isPresenting = isPresenting
        
        storeController.loadProducts()
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
    
    func showPaymentFailed() {
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

extension OnboardingViewModel: StoreControllerDelegate {
    
    func payForCreateAccount() throws {
        setPaymentState(.loading)
        
        try storeController.pay(for: .createAccount)
    }
    
    nonisolated
    func handlePayment(payment: Result<StoreController.Payment, any Error>) {
        Task {
            switch payment {
            case .success(let payment):
                if payment.productIdentifier == StoreController.Product.createAccount.rawValue {
                    try await completeAccountUpgrade()
                    await setPaymentState(.success)
                    
                    try await Task.delay(seconds: 250)
                    await dismiss()
                }
                
            case .failure:
                await showPaymentFailed()
                await setPaymentState(.normal)
            }
        }
    }
    
    private func completeAccountUpgrade() async throws {
        
        // 1. Update account from anonymous to a named one
        try await flipClient.setDisplayName(name: enteredName, owner: owner)
        
        // 2. Airdrop initial account Kin balance
        _ = try await client.airdrop(type: .getFirstKin, owner: owner)
    }
}

extension OnboardingViewModel {
    enum NavPath {
        case enterName
        case accessKey
        case finalizeCreation
    }
}
