//
//  EnterEmailScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-11.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterEmailScreen: View {

    @Bindable private var viewModel: VerificationViewModel

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(viewModel: VerificationViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 15) {
                Spacer()
                InputContainer(size: .regular) {
                    TextField("Email", text: $viewModel.enteredEmail)
                        .font(.appTextXL)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .multilineTextAlignment(.leading)
                        .padding([.leading, .trailing], 15)
                        .focused($isFocused)
                }

                Text("Please enter your email to continue")
                    .foregroundStyle(.textSecondary)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)

                Spacer()

                CodeButton(
                    state: viewModel.sendEmailCodeState,
                    style: .filled,
                    title: "Next",
                    disabled: !viewModel.canSendEmailVerification
                ) {
                    isFocused = false
                    viewModel.sendEmailCodeAction()
                }
            }
            .padding(20)
            .foregroundStyle(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFocused = true
        }
    }
}
