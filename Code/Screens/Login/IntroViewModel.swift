//
//  IntroViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-08-10.
//

import SwiftUI
import CodeServices
import CodeUI

@MainActor
class IntroViewModel: ObservableObject {
    
    let container: AppContainer
    
    @Published var isShowingPhoneVerificationScreen = false
    @Published var isShowingLoginScreen = false
    @Published var isShowingSecretRecoveryScreen = false

    @Published var isShowingPushPermissionsScreen = false
    @Published var isShowingCameraPermissionsScreen = false
    @Published var isShowingCameraPermissionsAfterPushScreen = false
    
    @Published var isShowingPrivacyPolicy = false
    @Published var isShowingTermsOfService = false
    
    @Published var createAccountButtonState: ButtonState = .normal
 
    private(set) var inflighMnemonic: MnemonicPhrase = .generate(.words12)
    
    private let cameraAuthorizer: CameraAuthorizer
    private let bannerController: BannerController
    private let sessionAuthenticator: SessionAuthenticator
    private let pushController: PushController
    
    private var initializedAccount: InitializedAccount?
    
    // MARK: - Init -
    
    init(container: AppContainer) {
        self.container = container
        self.cameraAuthorizer = container.cameraAuthorizer
        self.bannerController = container.bannerController
        self.sessionAuthenticator = container.sessionAuthenticator
        self.pushController = container.pushController
    }
    
    // MARK: - Actions -
    
    func startAccountCreation() {
        regenerateMnemonic()
        trace(.note, components: "Initiating create for owner: \(inflighMnemonic.solanaKeyPair().publicKey.base58)")
        isShowingPhoneVerificationScreen = true
    }
    
    func startLogin() {
        isShowingLoginScreen = true
    }
    
    func showPrivacyPolicy() {
        isShowingPrivacyPolicy = true
    }
    
    func showTermsOfService() {
        isShowingTermsOfService = true
    }
    
    func completePhoneVerificationForAccountCreation(phone: Phone, code: String, mnemonic: MnemonicPhrase) async throws {
        guard inflighMnemonic == mnemonic else {
            throw ErrorGeneric.unknown
        }
        
        isShowingSecretRecoveryScreen = true
    }
    
    private func regenerateMnemonic() {
        inflighMnemonic = .generate(.words12)
    }
    
    // MARK: - Account Creation -
    
    func promptSaveScreeshot() {
        Task {
            do {
                try await PhotoLibrary.saveSecretRecoveryPhraseSnapshot(for: inflighMnemonic)
                createAccount()
            } catch {
                bannerController.show(
                    style: .error,
                    title: Localized.Error.Title.failedToSave,
                    description: Localized.Error.Description.failedToSave,
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
        bannerController.show(
            style: .error,
            title: Localized.Prompt.Title.wroteThemDown,
            description: Localized.Prompt.Description.wroteThemDown,
            position: .bottom,
            actions: [
                .destructive(title: Localized.Action.yesWroteThemDown) { [weak self] in
                    self?.createAccount()
                },
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
    
    func copyWords() {
        UIPasteboard.general.string = inflighMnemonic.phrase
    }
    
    func exitAccountCreation() {
        bannerController.show(
            style: .error,
            title: Localized.Prompt.Title.exitAccountCreation,
            description: Localized.Prompt.Description.exitAccountCreation,
            position: .bottom,
            actionStyle: .stacked,
            actions: [
                .destructive(title: Localized.Action.exit) { [weak self] in
                    self?.isShowingPhoneVerificationScreen = false
                    self?.isShowingSecretRecoveryScreen = false
                },
                .cancel(title: Localized.Action.cancel),
            ]
        )
    }
    
    // MARK: - Permissions -
    
    private func requiresCameraPermissionsPrompt() -> Bool {
        cameraAuthorizer.status != .authorized
    }
    
    private func requiresPushPermissionsPrompt() -> Bool {
        pushController.authorizationStatus == .notDetermined
    }
    
    private func requestPermissionsIfNeeded() -> Bool {
        guard !requiresPushPermissionsPrompt() else {
            isShowingPushPermissionsScreen = true
            return true
        }
        
        guard !requiresCameraPermissionsPrompt() else {
            isShowingCameraPermissionsScreen = true
            return true
        }
        
        return false
    }
    
    func promptPushAccess() {
        pushController.authorize { _ in
            if self.requiresCameraPermissionsPrompt() {
                self.isShowingCameraPermissionsAfterPushScreen = true
            } else {
                self.finalizeAccountCreation()
            }
        }
    }
    
    func skipPushAccess() {
        self.isShowingCameraPermissionsAfterPushScreen = true
    }
    
    func promptCameraAccess() {
        cameraAuthorizer.authorize { status in
            if status == .authorized {
                self.finalizeAccountCreation()
            } else {
                self.bannerController.show(
                    style: .error,
                    title: Localized.Error.Title.cameraAccessRequired,
                    description: Localized.Error.Description.cameraAccessRequired,
                    actions: [
                        .cancel(title: Localized.Action.cancel),
                        .standard(title: Localized.Action.openSettings) {
                            URL.openSettings()
                        },
                    ]
                )
            }
        }
    }
    
    // MARK: - Actions -
    
    private func createAccount() {
        createAccountButtonState = .loading
        Task {
            do {
                self.initializedAccount = try await sessionAuthenticator.initialize(using: inflighMnemonic)
                try await Task.delay(seconds: 1)
                createAccountButtonState = .success
                try await Task.delay(seconds: 1)
                
                let needsPermissions = requestPermissionsIfNeeded()
                if !needsPermissions {
                    self.finalizeAccountCreation()
                }
                
                Analytics.createAccount(
                    isSuccessful: true,
                    ownerPublicKey: inflighMnemonic.solanaKeyPair().publicKey,
                    error: nil
                )
                    
            }
//            catch ErrorCreateIntent.denied {
//                createAccountButtonState = .normal
//                bannerController.show(
//                    style: .error,
//                    title: Localized.Error.Title.tooManyAccounts,
//                    description: Localized.Error.Description.tooManyAccounts,
//                    actions: [
//                        .cancel(title: Localized.Action.ok)
//                    ]
//                )
//                
//            }
            catch ErrorSubmitIntent.denied(let reasons) {
                defer {
                    createAccountButtonState = .normal
                }
                
                guard !reasons.isEmpty && reasons.first != .unspecified else {
                    showSomethingWentWrongError()
                    return
                }
                
                let reason = reasons[0]
                
                switch reason {
                case .unspecified:
                    // Handled above
                    break
                    
                case .tooManyFreeAccountsForPhoneNumber:
                    showTooManyAccountsPerPhoneError()
                    
                case .tooManyFreeAccountsForDevice:
                    showTooManyAccountsPerDeviceError()
                    
                case .unsupportedCountry:
                    showUnsupportedCountryError()
                    
                case .unsupportedDevice:
                    showUnsupportedDeviceError()
                }
            }
            
            catch {
                createAccountButtonState = .normal
                showSomethingWentWrongError()
                
                Analytics.createAccount(
                    isSuccessful: false,
                    ownerPublicKey: nil,
                    error: error
                )
            }
        }
    }
    
    private func finalizeAccountCreation() {
        guard let initializedAccount = initializedAccount else {
            return
        }
        
        sessionAuthenticator.completeLogin(with: initializedAccount)
    }
    
    // MARK: - Errors -
    
    private func showSomethingWentWrongError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.failedToCreateAccount,
            description: Localized.Error.Description.failedToCreateAccount,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showTooManyAccountsPerPhoneError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.tooManyAccountsPerPhone,
            description: Localized.Error.Description.tooManyAccountsPerPhone,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showTooManyAccountsPerDeviceError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.tooManyAccountsPerDevice,
            description: Localized.Error.Description.tooManyAccountsPerDevice,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showUnsupportedCountryError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.countryNotSupported,
            description: Localized.Error.Description.countryNotSupported,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showUnsupportedDeviceError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.deviceNotSupported,
            description: Localized.Error.Description.deviceNotSupported,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}
