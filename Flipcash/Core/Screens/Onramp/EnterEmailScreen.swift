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

    @Bindable private var onrampCoordinator: OnrampCoordinator

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(onrampCoordinator: OnrampCoordinator) {
        self.onrampCoordinator = onrampCoordinator
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 15) {
                Spacer()
                InputContainer(size: .regular) {
                    TextField("Email", text: $onrampCoordinator.enteredEmail)
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
                    .foregroundColor(.textSecondary)
                    .font(.appTextSmall)
                    .multilineTextAlignment(.center)

                Spacer()

                CodeButton(
                    state: onrampCoordinator.sendEmailCodeState,
                    style: .filled,
                    title: "Next",
                    disabled: !onrampCoordinator.canSendEmailVerification
                ) {
                    isFocused = false
                    onrampCoordinator.sendEmailCodeAction()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .dialog(item: $onrampCoordinator.dialogItem)
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFocused = true
        }
    }
}
