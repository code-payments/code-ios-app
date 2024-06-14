//
//  VerifyPhoneViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-08-04.
//

import UIKit
import SwiftUI
import CodeServices
import CodeUI

@MainActor
class VerifyPhoneViewModel: ObservableObject {

    @Published var isFocused: Bool = false
    @Published var enteredCode: String = ""
    @Published var enteredInviteCode: String = ""

    @Published var isShowingConfirmCodeScreen: Bool = false
    @Published var isShowingConfirmCodeScreenFromInvite: Bool = false
    
    @Published private(set) var region: Region
    @Published private(set) var enteredPhone: String = ""
    
    @Published private(set) var sendCodeButtonState: ButtonState = .normal
    @Published private(set) var confirmCodeButtonState: ButtonState = .normal
    @Published private(set) var inviteCodeButtonState: ButtonState = .normal
    @Published private(set) var isResending: Bool = false    
    
    var countryFlagStyle: Flag.Style {
        .fiat(region)
    }
    
    var countryCode: String {
        "+\(phoneFormatter.countryCode(for: region)!)"
    }
    
    var phone: Phone? {
        Phone(enteredPhone)
    }
    
    var canSendVerificationCode: Bool {
        phone != nil
    }
    
    var canSendInviteCode: Bool {
        enteredInviteCode.count > 2 &&
        enteredInviteCode.count <= 32 &&
        CharacterSet(charactersIn: enteredInviteCode).subtracting(.alphanumerics).isEmpty
    }
    
    var isCodeComplete: Bool {
        enteredCode.count >= codeLength
    }
    
    var adjustingPhoneNumberBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredPhone
            
        } set: { [weak self] newValue in
            guard let self = self else { return }
            let cleanPhoneNumber = newValue.filter { character in
                CharacterSet.numbers.contains(character.unicodeScalars.first!)
            }
            
            let countryCode = self.phoneFormatter.countryCode(for: self.region)!
            self.enteredPhone = self.phoneFormatter.format("+\(countryCode)\(cleanPhoneNumber)")
        }
    }
    
    var adjustingCodeBinding: Binding<String> {
        Binding { [weak self] in
            guard let self = self else { return "" }
            return self.enteredCode
            
        } set: { [weak self] newValue in
            guard let self = self else { return }
            
            if newValue.count > self.codeLength {
                self.enteredCode = String(newValue.prefix(self.codeLength))
            } else {
                self.enteredCode = newValue
            }
        }
    }
    
    let codeLength = 6
    let maxAllowedAttempts: Int = 3
    var failedAttempts: Int = 0
    
    private let client: Client
    private let bannerController: BannerController
    private let mnemonic: MnemonicPhrase
    private let phoneFormatter = PhoneFormatter()
    private let completion: (Phone, String, MnemonicPhrase) async throws -> Void
    
    // MARK: - Init -
    
    init(client: Client, bannerController: BannerController, mnemonic: MnemonicPhrase, completion: @escaping (Phone, String, MnemonicPhrase) async throws -> Void) {
        self.client = client
        self.bannerController = bannerController
        self.mnemonic = mnemonic
        self.completion = completion
        
        _region = Published(initialValue: phoneFormatter.currentRegion)
    }
    
    // MARK: - Actions -
    
    func changeRegion(region: Region) {
        self.region = region
    }
    
    func openCodeHomePage() {
        URL.codeHomePage.openWithApplication()
    }
    
    func resetInviteCode() {
        enteredInviteCode = ""
    }
    
    func sendCode() {
        guard let phone = phone else {
            return
        }
        
        isFocused = false
        sendCodeButtonState = .loading
        Task {
            do {
                try await client.sendCode(phone: phone)
                try await Task.delay(milliseconds: 500)
                sendCodeButtonState = .success
                try await Task.delay(milliseconds: 500)
                isShowingConfirmCodeScreen = true
                try await Task.delay(milliseconds: 500)
                sendCodeButtonState = .normal
                
            }
            
            catch ErrorSendCode.invalidPhoneNumber, ErrorSendCode.unsupportedPhoneNumber {
                sendCodeButtonState = .normal
                showUnsupportedESimError()
            }
            
            catch ErrorSendCode.unsupportedCountry {
                sendCodeButtonState = .normal
                showUnsupportedCountryError()
            }
            
            catch ErrorSendCode.unsupportedDevice {
                sendCodeButtonState = .normal
                showUnsupportedDeviceError()
            }
            
            catch {
                sendCodeButtonState = .normal
                showGenericError()
            }
        }
    }
    
    func resendCode() async throws -> Bool {
        guard let phone = phone else {
            return false
        }
        
        isResending = true
        defer {
            isResending = false
        }
        
        do {
            try await client.sendCode(phone: phone)
            return true
        } catch {
            showError()
            return false
        }
    }
    
    func confirmCode() {
        guard let phone = phone else {
            return
        }
        
        confirmCodeButtonState = .loading
        
        let owner = mnemonic.solanaKeyPair()
        Task {
            do {
                try await client.validate(phone: phone, code: enteredCode)
                try await client.linkAccount(phone: phone, code: enteredCode, owner: owner)
                try await Task.delay(milliseconds: 500)
                isFocused = false
                confirmCodeButtonState = .success
                try await Task.delay(milliseconds: 500)
                try await completion(phone, enteredCode, mnemonic)
                try await Task.delay(milliseconds: 500)
                confirmCodeButtonState = .normal
                enteredCode = ""
                
            } catch ErrorValidateCode.invalidCode {
                enteredCode = ""
                confirmCodeButtonState = .normal
                isFocused = true
                
                failedAttempts += 1
                if failedAttempts >= maxAllowedAttempts {
                    failedAttempts = 0
                    isShowingConfirmCodeScreen = false
                    Task {
                        try await Task.delay(milliseconds: 500)
                        showMaximumAttemptsReachedError()
                    }
                } else {
                    showInvalidCodeError()
                }
                
            } catch ErrorValidateCode.noVerification {
                enteredCode = ""
                confirmCodeButtonState = .normal
                isShowingConfirmCodeScreen = false
                Task {
                    try await Task.delay(milliseconds: 500)
                    showTimeoutError()
                }
            } catch {
                enteredCode = ""
                confirmCodeButtonState = .normal
                isFocused = true
                showError()
            }
        }
    }
    
    func confirmInvite() {
        guard let phone = phone else {
            return
        }
        
        isFocused = false
        inviteCodeButtonState = .loading
        Task {
            do {
                try await client.sendCode(phone: phone)
                try await Task.delay(milliseconds: 500)
                inviteCodeButtonState = .success
                try await Task.delay(milliseconds: 500)
                isShowingConfirmCodeScreenFromInvite = true
                try await Task.delay(milliseconds: 500)
                inviteCodeButtonState = .normal
                
            } catch {
                inviteCodeButtonState = .normal
            }
        }
    }
    
    // MARK: - Clipboard -
    
    func pasteCodeFromClipboardIfPossible() {
        guard let code = codeFromClipboard() else {
            return
        }
        
        enteredCode = code
    }
    
    private func codeFromClipboard() -> String? {
        if let codeString = UIPasteboard.general.string, codeString.count == codeLength {
            let digits: [Int] = codeString.utf8.compactMap { char in
                let digit = Int(char)
                if digit >= 48 && digit <= 57 {
                    return digit
                }
                return nil
            }
            
            if digits.count == codeLength {
                return codeString
            }
        }
        return nil
    }
    
    // MARK: - Phone Errors -
    
//    private func showNotInvitedError() {
//        bannerController.show(
//            style: .warning,
//            title: Localized.Error.Title.notInvitedYet,
//            description: Localized.Error.Description.notInvitedYet("getcode.com"),
//            actions: [
//                .standard(title: Localized.Action.joinWaitlist) {
//                    self.openCodeHomePage()
//                },
//                .cancel(title: Localized.Action.ok)
//            ]
//        )
//    }
    
    func showGenericError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.failedToSendCode,
            description: Localized.Error.Description.failedToSendCode,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    // MARK: - Code Errors -
    
    private func showError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.failedToVerifyPhone,
            description: Localized.Error.Description.failedToVerifyPhone,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showInvalidCodeError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.invalidVerificationCode,
            description: Localized.Error.Description.invalidVerificationCode,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showMaximumAttemptsReachedError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.maxAttemptsReached,
            description: Localized.Error.Description.maxAttemptsReached,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
    private func showTimeoutError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.codeTimedOut,
            description: Localized.Error.Description.codeTimedOut,
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
    
    private func showUnsupportedESimError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.eSimNotSupported,
            description: Localized.Error.Description.eSimNotSupported,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
}

// MARK: - CharacterSet -

private extension CharacterSet {
    static let numbers: CharacterSet = CharacterSet(charactersIn: "0123456789")
}
