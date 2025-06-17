//
//  OnboardingViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-05.
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import StoreKit

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
    private let flipClient: FlipClient
    private let sessionAuthenticator: SessionAuthenticator
    private let cameraAuthorizer: CameraAuthorizer
    
    private var initializedAccount: InitializedAccount?
    
    private var isPurchasePending: Bool = true
    
    // MARK: - Init -
    
    init(container: Container) {
        self.container            = container
        self.client               = container.client
        self.flipClient           = container.flipClient
        self.sessionAuthenticator = container.sessionAuthenticator
        self.storeController      = container.storeController
        self.cameraAuthorizer     = CameraAuthorizer()
        
        storeController.delegate = self
        
        if let _ = UserDefaults.pendingPurchase {
            path = [.purchasePending]
        } else if let mnemonic = Keychain.onboardingMnemonic {
            inflightMnemonic = mnemonic
            navigateToBuyAccountScreen()
        }
        
        processAsynTransactionsIfNeeded()
    }
    
    // MARK: - Action -
    
    func loginAction() {
        navigateToLogin()
    }
    
    func createAccountAction() {
        if let mnemonic = Keychain.onboardingMnemonic {
            inflightMnemonic = mnemonic
        } else {
            inflightMnemonic = MnemonicPhrase.generate(.words12)
        }
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
            
            let mnemonic = inflightMnemonic
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: mnemonic)
                
                // Store onboarding mnemonic is it has
                // been saved to photos so we can resume
                // the flow if the account isn't paid for
                Keychain.onboardingMnemonic = mnemonic
                
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
                    .destructive("Open Settings") {
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
        let mnemonic = inflightMnemonic
        Task {
            let owner    = mnemonic.solanaKeyPair()
            let product  = IAPProduct.createAccount
            let uniqueID = UUID()
            
            do {
                let result = try await storeController.pay(
                    for: product,
                    owner: owner,
                    uniqueID: uniqueID
                )
                
                switch result {
                case .success(let purchase, let finishTransaction):
                    
                    // Reset onboarding mnemonic after
                    // the account has been paid for
                    Keychain.onboardingMnemonic = nil
                    
                    try await registerAccount(
                        for: purchase,
                        finishTransaction: finishTransaction,
                        mnemonic: mnemonic,
                        uniqueID: uniqueID
                    )
                    
                case .pending:
                    setPurchasePending(
                        for: mnemonic,
                        product: product,
                        uniqueID: uniqueID
                    )
                    
                case .failed, .cancelled:
                    break
                }
                
                try await Task.delay(milliseconds: 350)
                buyAccountButtonState = .normal
                
            } catch {
                ErrorReporting.captureError(error)
                
                dialogItem = .init(
                    style: .destructive,
                    title: "Something Went Wrong",
                    subtitle: "We couldn't create your account. Please try again.",
                    dismissable: true
                ) {
                    .okay(kind: .destructive)
                }
                buyAccountButtonState = .normal
            }
        }
    }
    
    func allowCameraAccessAction() {
        Task {
            do {
                // Regardless of authorization status
                // continue to finalize the account,
                // they'll have an opportunity to grant
                // access on the camera screen
                _ = try await cameraAuthorizer.authorize()
            } catch {}
            completeOnboardingAndLogin()
        }
    }
    
    func cancelPendingPurchaseAction() {
        UserDefaults.pendingPurchase = nil
        Keychain.onboardingMnemonic = nil
        
        navigateToRoot()
        
        Analytics.cancelPendingPurchase()
    }
    
    func allowPushPermissionsAction() {
        Task {
            do {
                try await PushController.authorize()
            } catch {}
            navigateToCameraAccessScreen()
        }
    }
    
    func skipPushPermissionsAction() {
        navigateToCameraAccessScreen()
    }
    
    // MARK: - Purchase -
    
    private func registerAccount(for purchase: StoreController.Purchase, finishTransaction: StoreController.FinishTransaction, mnemonic: MnemonicPhrase, uniqueID: UUID) async throws {
        let owner = mnemonic.solanaKeyPair()
        
        let price = purchase.price?.doubleValue ?? -1
        let currency = purchase.currencyCode ?? "nil"
        
        Analytics.createAccountPayment(
            price: price,
            currency: currency,
            owner: owner.publicKey
        )
        
        try await flipClient.register(owner: owner)
        try await flipClient.completePurchase(
            receipt: purchase.receipt,
            productID: purchase.productID,
            price: price,
            currency: currency,
            owner: owner
        )
        
        await finishTransaction()
        
        let account = try await sessionAuthenticator.initialize(
            using: mnemonic,
            isRegistration: true
        )
        
        initializedAccount = account
        
        buyAccountButtonState = .success
        try await Task.delay(seconds: 1)
        
        navigateToPushPermissionsScreen()
    }
    
    // MARK: - Account Creation -
    
    private func completeOnboardingAndLogin() {
        guard let initializedAccount else {
            return
        }
        
        sessionAuthenticator.completeLogin(with: initializedAccount)
    }
    
    // MARK: - Pending Transactions -
    
    private func setPurchasePending(for mnemonic: MnemonicPhrase, product: IAPProduct, uniqueID: UUID) {
        UserDefaults.pendingPurchase = .init(
            uniqueID: uniqueID,
            mnemonic: mnemonic,
            product: product,
            date: .now
        )
        
        navigateToPurchasePendingScreen()
    }
    
    private func processAsynTransactionsIfNeeded() {
        if !storeController.pendingPurchaseResults.isEmpty {
            trace(.note, components: "Processing outstanding pending transactions...")
            
            for result in storeController.pendingPurchaseResults {
                // Only process one at a time
                let processed = processAsyncPurchaseResult(result: result)
                if processed {
                    return
                }
            }
        }
    }
    
    @discardableResult
    private func processAsyncPurchaseResult(result: StoreController.PurchaseResult) -> Bool {
        switch result {
        case .success(let purchase, let finishTransaction):
            
            // Only process account purchases, only one at a time
            if purchase.productID == IAPProduct.createAccount.rawValue {
                trace(.success, components: "Processing successful purchase for: \(purchase.productID), uuid: \(purchase.uniqueID.uuidString)")
                
                guard let pendingPurchase = UserDefaults.pendingPurchase else {
                    return false
                }
                
                trace(.note, components: "Found stored pending purchase for: \(pendingPurchase.uniqueID.uuidString)")
                
                guard pendingPurchase.uniqueID == purchase.uniqueID else {
                    trace(.failure, components: "Store pending purchase: \(pendingPurchase.uniqueID.uuidString) doesn't match purchase: \(purchase.uniqueID.uuidString)")
                    return false
                }
                
                Task {
                    do {
                        try await registerAccount(
                            for: purchase,
                            finishTransaction: finishTransaction,
                            mnemonic: pendingPurchase.mnemonic,
                            uniqueID: pendingPurchase.uniqueID
                        )
                    } catch {
                        ErrorReporting.captureError(error)
                    }
                }
                
                UserDefaults.pendingPurchase = nil
                return true
            }
            
        case .pending, .cancelled, .failed:
            break
        }
        
        return false
    }
    
    // MARK: - Navigation -
    
    func navigateToRoot() {
        path = []
    }
    
    func navigateToLogin() {
        path = [.login]
    }
    
    func navigateToAccessKey() {
        path = [.accessKey]
    }
    
    func navigateToPurchasePendingScreen() {
        path.append(.purchasePending)
    }
    
    func navigateToBuyAccountScreen() {
        path.append(.buyAccount)
    }
    
    func navigateToCameraAccessScreen() {
        path.append(.cameraAccess)
    }
    
    func navigateToPushPermissionsScreen() {
        path.append(.pushPermissions)
    }
}

// MARK: - StoreControllerDelegate -

extension OnboardingViewModel: StoreControllerDelegate {
    func storeController(_ controller: StoreController, didReceivePurchaseResult result: StoreController.PurchaseResult) {
        processAsyncPurchaseResult(result: result)
    }
}

// MARK: - Path -

enum OnboardingPath {
    case login
    case accessKey
    case buyAccount
    case pushPermissions
    case cameraAccess
    case purchasePending
}

// MARK: - PendingPurchase -

struct PendingPurchase: Codable, Hashable, Equatable, Sendable {
    let uniqueID: UUID
    let mnemonic: MnemonicPhrase
    let product: IAPProduct
    let date: Date
}

// MARK: - Defaults -

private extension UserDefaults {
    
    @Defaults(.pendingPurchase)
    static var pendingPurchase: PendingPurchase?
}

// MARK: - Keychain -

private extension Keychain {
    @SecureCodable(.onboardingMnemonic)
    static var onboardingMnemonic: MnemonicPhrase?
}
