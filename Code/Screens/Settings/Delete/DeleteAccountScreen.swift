//
//  DeleteAccountScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-10-04.
//

import SwiftUI
import CodeUI
import CodeServices

struct DeleteAccountScreen: View {
    
    @StateObject private var viewModel: DeleteAccountViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> DeleteAccountViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 30) {
                NavigationLink(isActive: $viewModel.showingDeleteConfirmation) {
                    LazyView(
                        ConfirmDeleteScreen(viewModel: viewModel)
                    )
                } label: {
                    EmptyView()
                }
                
                Image.asset(.deleteBubble)
                
                section(
                    title: Localized.DeleteAccount.Title.willDo,
                    description: Localized.DeleteAccount.Description.willDo
                )
                
                section(
                    title: Localized.DeleteAccount.Title.wontDo,
                    description: Localized.DeleteAccount.Description.wontDo
                )
                
                section(
                    title: Localized.DeleteAccount.Title.willHappen,
                    description: Localized.DeleteAccount.Description.willHappen
                )
                
                Spacer()
                
                CodeButton(style: .filled, title: Localized.Action.continue) {
                    viewModel.continueToAccountDeletion()
                }
            }
            .foregroundColor(.textMain)
            .padding(20)
        }
        .navigationBarTitle(Text(Localized.Action.deleteAccount), displayMode: .inline)
        .onAppear {
            Analytics.open(screen: .deleteAccount)
            ErrorReporting.breadcrumb(.deleteAccountScreen)
        }
    }
    
    @ViewBuilder private func section(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.appTextLarge)
            Text(description)
                .font(.appTextSmall)
        }
        .multilineTextAlignment(.leading)
    }
}

// MARK: - Previews -

struct DeleteAccountScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DeleteAccountScreen(
                viewModel: DeleteAccountViewModel(sessionAuthenticator: .mock, bannerController: .mock)
            )
        }
        .environmentObjectsForSession()
    }
}
