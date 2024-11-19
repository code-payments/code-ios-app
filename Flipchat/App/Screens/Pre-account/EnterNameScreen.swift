//
//  EnterNameScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct EnterNameScreen: View {
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var banners: Banners
    
    @ObservedObject private var viewModel: OnboardingViewModel
    
    @FocusState private var isFocused: Bool
    
    // MARK: - Init -
    
    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 40) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Your Name", text: $viewModel.enteredName)
                        .focused($isFocused)
                        .font(.appDisplayMedium)
                        .frame(maxWidth: .infinity)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.leading)
                        .padding([.leading, .trailing], 0)
                    
                    Text("This is how you'll show up in chats")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                }
                .foregroundStyle(Color.textMain)
                
                Spacer()
                
                CodeButton(
                    state: viewModel.accountCreationState,
                    style: .filled,
                    title: Localized.Action.next,
                    disabled: !viewModel.isEnteredNameValid
                ) {
                    hideKeyboard()
                    viewModel.registerEnteredName()
                }
            }
            .foregroundColor(.textMain)
            .frame(maxHeight: .infinity)
            .padding(20)
        }
        .navigationBarTitle(Text(""), displayMode: .inline)
        .onAppear(perform: onAppear)
    }
    
    private func onAppear() {
        showKeyboard()
    }
    
    private func showKeyboard() {
        isFocused = true
    }
    
    private func hideKeyboard() {
        isFocused = false
    }
}

#Preview {
    EnterRoomNumberScreen(viewModel: .mock)
}
