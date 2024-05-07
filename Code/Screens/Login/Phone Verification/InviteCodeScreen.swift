//
//  InviteCodeScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-04-04.
//

import SwiftUI
import CodeUI
import CodeServices
import SwiftUIIntrospect

struct InviteCodeScreen: View {
    
    @Binding private var isActive: Bool
    
    @State private var textField: UITextField?
    
    @StateObject private var viewModel: VerifyPhoneViewModel
    
    private let showCloseButton: Bool
    
    // MARK: - Init -
    
    init(isActive: Binding<Bool>, showCloseButton: Bool, viewModel: @autoclosure @escaping () -> VerifyPhoneViewModel) {
        self._isActive   = isActive
        self.showCloseButton = showCloseButton
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 15) {
                Flow(isActive: $viewModel.isShowingConfirmCodeScreenFromInvite) {
                    ConfirmPhoneScreen(
                        isActive: $isActive,
                        showCloseButton: showCloseButton,
                        viewModel: viewModel
                    )
                }
                
                Spacer()
                InputContainer(size: .regular) {
                    TextField(Localized.Subtitle.inviteCode, text: $viewModel.enteredInviteCode)
                        .font(.appTextXL)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        //.textContentType(.username)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .multilineTextAlignment(.center)
                        .introspect(.textField, on: .iOS(.v15, .v16, .v17)) { field in
                            textField = field
                        }
                        .padding([.leading, .trailing], 15)
                }
                
                Text(Localized.Subtitle.inviteCodeDescription)
                    .foregroundColor(.textSecondary)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.inviteCodeButtonState,
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.canSendInviteCode
                ) {
                    viewModel.confirmInvite()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .navigationBarTitle(Text(Localized.Subtitle.inviteCode), displayMode: .inline)
        .if(showCloseButton) { $0
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton {
                        isActive.toggle()
                    }
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .inviteCode)
            ErrorReporting.breadcrumb(.inviteCodeScreen)
            viewModel.resetInviteCode()
            Task {
                // Currently overloaded to imply that this
                // view is presented modally which has smaller
                // delay requirements for presenting the keyboard
                if showCloseButton {
                    try await Task.delay(milliseconds: 100)
                } else {
                    try await Task.delay(milliseconds: 500)
                }
                viewModel.isFocused = true
            }
        }
        .onChange(of: viewModel.isFocused) { isFocused in
            if isFocused {
                textField?.becomeFirstResponder()
            } else {
                _ = textField?.resignFirstResponder()
            }
        }
    }
}

// MARK: - Previews -

struct InviteCodeScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            InviteCodeScreen(
                isActive: .constant(true),
                showCloseButton: false,
                viewModel: VerifyPhoneViewModel(
                    client: .mock,
                    bannerController: .mock,
                    mnemonic: .mock,
                    completion: { _, _, _ in }
                )
            )
        }
        .preferredColorScheme(.dark)
    }
}
