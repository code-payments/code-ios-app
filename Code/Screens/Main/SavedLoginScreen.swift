//
//  SavedLoginScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-06-27.
//

import SwiftUI
import CodeUI
import CodeServices

struct SavedLoginScreen: View {
    
    @EnvironmentObject private var exchange: Exchange
    
    @ObservedObject private var client: Client
    @ObservedObject private var sessionAuthenticator: SessionAuthenticator
    
    @StateObject private var accountContainer: AccountContainer
    
    @State private var buttonState: ButtonState = .normal
    @State private var selectedIndex: Int = 0
    
    private var accounts: [HistoricalAccount] {
//        []
//        [
//            HistoricalAccount(
//                details: AccountDescription.mockMany()[0]
//            ),
//            HistoricalAccount(
//                details: AccountDescription.mockMany()[1]
//            ),
//        ]
        accountContainer.accounts
            .filter {
                $0.organizer.availableBalance > 0
            }
            .sorted { lhs, rhs in
                lhs.organizer.availableBalance > rhs.organizer.availableBalance
            }
    }
    
    // MARK: - Init -
    
    init(client: Client, sessionAuthenticator: SessionAuthenticator) {
        self.client = client
        self.sessionAuthenticator = sessionAuthenticator
        
        let container = AccountContainer(
            client: client,
            accountManager: sessionAuthenticator.accountManager
        )
        
        self._accountContainer = .init(wrappedValue: container)
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                
                Text("You were logged out. Would you like to continue using this account?")
                    .font(.appTextMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(20)
                
                Spacer()
                
                if !accounts.isEmpty {
                    TabView(selection: $selectedIndex) {
                        ForEach(0..<accounts.count, id: \.self) { index in
                            VStack(spacing: 40) {
                                Spacer()
                                
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.backgroundRow)
                                    Image.asset(.codeLogo)
                                        .resizable()
                                        .padding(20)
                                }
                                .frame(width: 120, height: 120)
                                
                                VStack(spacing: 5) {
                                    HStack(spacing: 15) {
                                        Flag(style: CurrencyCode.cad.flagStyle, size: .regular)
                                        Text(formattedLocalValue(for: accounts[index]))
                                            .font(.appDisplayMedium)
                                    }
                                    
                                    KinText(accounts[index].formattedKin(), format: .large)
                                        .font(.appTextMedium)
                                        .foregroundColor(.textSecondary)
                                }
                                
                                Spacer()
                                Spacer()
                            }
                            .tag(index)
                        }
                    }
                    .padding(.horizontal, -20)
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                } else {
                    LoadingView(color: .textSecondary)
                }
                
                Spacer()
                
                // Bottom
                
                VStack(spacing: 5) {
                    CodeButton(
                        state: buttonState,
                        style: .filled,
                        title: Localized.Action.continue,
                        disabled: accounts.isEmpty
                    ) {
                        login(account: accounts[selectedIndex])
                    }
                    
                    CodeButton(
                        style: .subtle,
                        title: Localized.Action.notNow
                    ) {
                        cancel()
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            Task {
                await accountContainer.fetchAccounts()
            }
        }
    }
    
    private func formattedLocalValue(for account: HistoricalAccount) -> String {
        "\(account.formattedFiat(rate: exchange.localRate))"
    }
    
    // MARK: - Actions -
    
    private func login(account: HistoricalAccount) {
        Task {
            buttonState = .loading
            let initializedAccount = try await sessionAuthenticator.initialize(using: account.details.account.mnemonic)
            try await Task.delay(seconds: 1)
            buttonState = .success
            try await Task.delay(seconds: 1)
            sessionAuthenticator.completeLogin(with: initializedAccount)
        }
    }
    
    private func cancel() {
        sessionAuthenticator.logout()
    }
}

struct SavedLoginScreen_Previews: PreviewProvider {
    static var previews: some View {
        SavedLoginScreen(
            client: .mock,
            sessionAuthenticator: .mock
        )
        .environmentObjectsForSession()
    }
}
