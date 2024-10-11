//
//  LoginScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import SwiftUI
import CodeUI
import CodeServices

struct LoginScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var bannerController: BannerController
    
    @State private var buttonState: ButtonState = .normal
    @State private var inputText: String = ""
    @State private var autocompleteResults: [String] = []
    
    @State private var inputChangeCount: Int = 0
    @State private var autoCompleteCount: Int = 0
    
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
                    Text(Localized.Subtitle.loginDescription)
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    InputContainer(size: .custom(120)) {
                        TextEditor(text: $inputText)
                            .focused($isFocused)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .backportScrollContentBackground(.hidden)
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
                            title: Localized.Action.logIn,
                            disabled: enteredMnemonic() == nil,
                            action: attemptLogin
                        )
                        
                        if betaFlags.accessGranted {
                            CodeButton(
                                style: .subtle,
                                title: Localized.Action.recoverExistingAccount,
                                disabled: !buttonState.isNormal
                            ) {
                                isShowingAccountSelection.toggle()
                            }
                            .sheet(isPresented: $isShowingAccountSelection) {
                                AccountSelectionScreen(
                                    isPresented: $isShowingAccountSelection,
                                    sessionAuthenticator: sessionAuthenticator,
                                    action: recoverExistingAccount
                                )
                                .environmentObject(client)
                                .environmentObject(exchange)
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
        .navigationBarTitle(Text(Localized.Title.enterAccessKeyWords), displayMode: .inline)
        .onChange(of: inputText) {
            suggestAutoCompleteResults(for: inputText)
        }
    }
    
    // MARK: - Actions -
    
    private func attemptLogin() {
        guard buttonState.isNormal, let mnemonic = enteredMnemonic() else {
            return
        }
        
        dismissKeyboard()
        
        Task {
            try await login(mnemonic: mnemonic)
        }
    }
        
    private func recoverExistingAccount(accountDescription: AccountDescription) {
        isShowingAccountSelection = false
        
        dismissKeyboard()
        
        Task {
            try await login(mnemonic: accountDescription.account.mnemonic)
        }
    }
    
    private func login(mnemonic: MnemonicPhrase) async throws {
        let owner = mnemonic.solanaKeyPair()
        
        buttonState = .loading
        
        // First step is to check whether or not this account
        // requires phone number verification. If `notFound`
        // then we know that there was never a phone number
        // that verified this account.
        do {
            _ = try await client.fetchAssociatedPhoneNumber(owner: owner)
            
            // There are 3 scenarios here:
            // 1. PhoneLink is non-nil, phone is linked
            //    This is a recent account, login normally
            //
            // 2. PhoneLink is non-nil, phone is not linked
            //    Account previously verified, can login
            //
            // 3. PhoneLink is nil
            //    This account was never verified with a phone
            //    number and requires verification before login
            
            let initializedAccount = try await sessionAuthenticator.initialize(using: mnemonic)
            try await Task.delay(seconds: 1)
            buttonState = .success
            try await Task.delay(seconds: 1)
            sessionAuthenticator.completeLogin(with: initializedAccount)
            
            Analytics.login(
                ownerPublicKey: owner.publicKey,
                autoCompleteCount: autoCompleteCount,
                inputChangeCount: inputChangeCount
            ) 
        }
        
        catch ErrorFetchUser.unlockedTimelock, ErrorFetchAssociatedPhone.unlockedTimelock {
            try await Task.delay(milliseconds: 500)
            buttonState = .normal
            showUnlockedTimelockError()
        }
        
        catch { // ErrorFetchAssociatedPhone.notFound
            try await Task.delay(milliseconds: 500)
            buttonState = .normal
            showError()
        }
    }
    
    // MARK: - Errors -
    
    private func showError() {
        bannerController.show(
            style: .error,
            title: Localized.Prompt.Title.notCodeAccount,
            description: Localized.Prompt.Description.notCodeAccount,
            position: .top,
            actions: [
                .cancel(title: Localized.Action.tryDifferentCodeAccount),
            ]
        )
    }
    
    private func showUnlockedTimelockError() {
        bannerController.show(
            style: .error,
            title: Localized.Error.Title.timelockUnlocked,
            description: Localized.Error.Description.timelockUnlocked,
            actions: [
                .cancel(title: Localized.Action.ok)
            ]
        )
    }
    
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
        inputChangeCount += 1
        
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
        autoCompleteCount += 1
        
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

// MARK: - Previews -

struct LoginScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LoginScreen()
        }
        .preferredColorScheme(.dark)
        .environmentObjectsForSession()
    }
}
