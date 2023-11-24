//
//  ConfirmDeleteScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-10-04.
//

import SwiftUI
import CodeUI
import CodeServices

struct ConfirmDeleteScreen: View {
    
    @StateObject private var viewModel: DeleteAccountViewModel
    
    @FocusState private var isFocused: Bool
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> DeleteAccountViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 30) {
                Text(Localized.Subtitle.deleteAccountDescription)
                    .font(.appTextSmall)
                    .foregroundColor(.textMain)
                
                InputContainer {
                    TextField(Localized.Subtitle.typeDelete(Localized.Subtitle.delete), text: $viewModel.confirmationText, onCommit: onCommit)
                        .font(.appTextMedium)
                        .padding(.horizontal, 15)
                        .focused($isFocused)
                }
                
                Spacer()
                
                CodeButton( style: .filled, title: Localized.Action.deleteAccount, disabled: !viewModel.canDeleteAccount) {
                    Task {
                        if isFocused {
                            isFocused = false
                            try await Task.delay(milliseconds: 300)
                        }
                        viewModel.deleteAccount()
                    }
                }
            }
            .padding(20)
        }
        .navigationBarTitle(Text(Localized.Action.deleteAccount), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .confirmDelete)
            ErrorReporting.breadcrumb(.confirmDeleteScreen)
        }
    }
    
    private func onCommit() {
        isFocused = false
    }
}

// MARK: - Previews -

struct ConfirmDeleteScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConfirmDeleteScreen(
                viewModel: DeleteAccountViewModel(sessionAuthenticator: .mock, bannerController: .mock)
            )
        }
        .environmentObjectsForSession()
    }
}
