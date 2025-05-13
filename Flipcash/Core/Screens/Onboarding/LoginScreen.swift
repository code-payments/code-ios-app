//
//  LoginScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct LoginScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @State private var buttonState: ButtonState = .normal
    @State private var inputText: String = ""
    @State private var autocompleteResults: [String] = []
    
    @State private var isShowingAccountSelection = false
    
    @FocusState private var isFocused: Bool
    
    private let language = Mnemonic.Language.english
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack {
                VStack(alignment: .center, spacing: 20) {
                    Text("Check your photos for the Access Key you saved when you first created your account.")
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    InputContainer(size: .custom(120)) {
                        TextEditor(text: $inputText)
                            .focused($isFocused)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .scrollContentBackground(.hidden)
                            .foregroundColor(.textMain)
                            .font(.appTextMedium)
                            .padding(10)
                            .padding(.bottom, 20)
                            .disabled(!buttonState.isNormal)
                            .overlay {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Text("\(words().count)")
                                        if let _ = enteredMnemonic() {
                                            Image.system(.circleCheck)
                                        }
                                        Spacer()
                                    }
                                    .foregroundColor(.textSecondary)
                                    .font(.appTextHeading)
                                    .padding(.leading, 10)
                                    .padding(.bottom, 7)
                                    
                                }
                            }
                    }
                    
                    VStack(spacing: 5) {
                        CodeButton(
                            state: buttonState,
                            style: .filled,
                            title: "Log In",
                            disabled: enteredMnemonic() == nil,
                            action: attemptLogin
                        )
                        
                        if betaFlags.accessGranted {
                            CodeButton(
                                style: .subtle,
                                title: "Recover Existing Account",
                                disabled: !buttonState.isNormal
                            ) {
                                isFocused = false
                                isShowingAccountSelection.toggle()
                            }
                            .sheet(isPresented: $isShowingAccountSelection) {
                                AccountSelectionScreen(
                                    isPresented: $isShowingAccountSelection,
                                    sessionAuthenticator: sessionAuthenticator,
                                    action: recoverExistingAccount
                                )
                                .environmentObject(client)
                            }
                        }
                    }
                }
                .foregroundColor(.textMain)
                .padding([.leading, .trailing, .top], 20)
                
                Spacer()
                
                HStack(alignment: .top) {
                    ForEach(autocompleteResults, id: \.self) { word in
                        Button {
                            autoCompleteLast(with: word)
                        } label: {
                            TextBubble(style: .filled, text: word)
                        }
                    }
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.bottom, 15)
            }
            .onAppear {
                showKeyboard()
            }
        }
        .navigationTitle("Enter Access Key Words")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: inputText) {
            suggestAutoCompleteResults(for: inputText)
        }
    }
    
    // MARK: - Actions -
    
    private func attemptLogin() {
        guard buttonState.isNormal, let mnemonic = enteredMnemonic() else {
            return
        }
        
        // Remove suggestions
        suggestAutoCompleteResults(for: "")
        
        dismissKeyboard()
        
        Task {
            try await login(mnemonic: mnemonic)
        }
    }
        
    private func recoverExistingAccount(accountDescription: AccountDescription) {
        isShowingAccountSelection = false
        
        dismissKeyboard()
        
        Task {
            buttonState = .loading
            try await login(mnemonic: accountDescription.account.mnemonic)
            try await Task.delay(milliseconds: 500)
            buttonState = .normal
        }
    }
    
    private func login(mnemonic: MnemonicPhrase) async throws {
        buttonState = .loading
        do {
            let initializedAccount = try await sessionAuthenticator.initialize(
                using: mnemonic,
                isRegistration: false
            )
            
            try await Task.delay(milliseconds: 500)
            buttonState = .success
            
            try await Task.delay(milliseconds: 500)
            sessionAuthenticator.completeLogin(with: initializedAccount)
            
//            Analytics.login(
//                ownerPublicKey: owner.publicKey,
//                autoCompleteCount: autoCompleteCount,
//                inputChangeCount: inputChangeCount
//            )
            
        } catch {
            try await Task.delay(milliseconds: 500)
            buttonState = .normal
//            showError()
        }
    }
    
    // MARK: - Errors -
    
//    private func showError() {
//        banners.show(
//            style: .error,
//            title: "Invalid Account",
//            description: "This is not a valid Flipchat account.",
//            position: .top,
//            actions: [
//                .cancel(title: Localized.Action.ok),
//            ]
//        )
//    }
//    
//    private func showUnlockedTimelockError() {
//        banners.show(
//            style: .error,
//            title: "Access Key No Longer Useable",
//            description: "Your Access Key has initiated an unlock. As a result, you will no longer be able to use this Access Key.",
//            actions: [
//                .cancel(title: Localized.Action.ok)
//            ]
//        )
//    }
    
    // MARK: - Auto-complete -
    
    private func words() -> [String] {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return []
        }
        
        
        return text.tokens()
    }
    
    private func enteredMnemonic() -> MnemonicPhrase? {
        MnemonicPhrase(words: words())
    }
    
    private func suggestAutoCompleteResults(for inputText: String) {
        let enteredWords = inputText.tokens()
        
        if let lastWord = enteredWords.last, !lastWord.isEmpty {
            let suggestions = language.words(startingWith: lastWord)
            if suggestions.count == 1, suggestions.first == lastWord {
                autocompleteResults = []
            } else {
                if suggestions.count > 3 {
                    autocompleteResults = Array(suggestions.prefix(through: 2))
                } else {
                    autocompleteResults = suggestions
                }
            }
        } else {
            autocompleteResults = []
        }
    }
    
    private func autoCompleteLast(with word: String) {
        var enteredWords = inputText.tokens()
        enteredWords.removeLast()
        enteredWords.append(word)
        inputText = "\(enteredWords.joinedTokens()) " // <- Insert space
    }
    
    private func showKeyboard() {
        isFocused = true
    }
    
    private func dismissKeyboard() {
        isFocused = true
    }
}

// MARK: - Extensions -

private extension String {
    func tokens() -> [String] {
        components(separatedBy: " ")
    }
}

private extension Array where Element == String {
    func joinedTokens() -> Element {
        joined(separator: " ")
    }
}
