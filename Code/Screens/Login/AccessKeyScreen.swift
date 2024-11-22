//
//  AccessKeyScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-04-13.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct AccessKeyScreen<Content>: View where Content: View {
    
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    private let content: () -> Content
    
    // MARK: - Init -
    
    @StateObject private var viewModel: IntroViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> IntroViewModel, @ViewBuilder content: @escaping () -> Content) {
        self._viewModel = StateObject(wrappedValue: viewModel())
        self.content = content
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                content()
                
                Spacer()
                
                VStack(alignment: .center, spacing: 20) {
                    AccessKey(
                        mnemonic: viewModel.inflighMnemonic,
                        url: .login(with: viewModel.inflighMnemonic)
                    )
                    .contextMenu(ContextMenu {
                        Button(action: copy) {
                            Label(Localized.Action.copy, systemImage: SystemSymbol.doc.rawValue)
                        }
                    })
                    
                    Text(Localized.Subtitle.accessKeyDescription)
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 40)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.createAccountButtonState,
                    style: .filled,
                    title: Localized.Action.saveAccessKey
                ) {
                    viewModel.promptSaveScreeshot()
                }
                
                CodeButton(
                    style: .subtle,
                    title: Localized.Action.wroteThemDownInstead,
                    disabled: sessionAuthenticator.inProgress
                ) {
                    viewModel.promptWrittenConfirmation()
                }
            }
            .ignoresSafeArea(.keyboard)
            .foregroundColor(.textMain)
            .padding(20)
            .navigationBarTitle(Text(Localized.Title.yourAccessKey), displayMode: .inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarCloseButton {
                        viewModel.exitAccountCreation()
                    }
                }
            }
        }
    }
    
    // MARK: - Copy / Paste -
    
    private func copy() {
        UIPasteboard.general.string = viewModel.inflighMnemonic.phrase
    }
}

// MARK: - Previews -

struct SecretRecoveryScreen_Previews: PreviewProvider {
    static var previews: some View {
        Preview(devices: .iPhoneSE, .iPhoneMini, .iPhoneMax) {
            NavigationView {
                AccessKeyScreen(viewModel: IntroViewModel(container: .mock)) {}
            }
        }
        .environmentObjectsForSession()
    }
}
