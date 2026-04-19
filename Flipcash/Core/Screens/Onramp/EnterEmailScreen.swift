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

    @Bindable private var coordinator: OnrampCoordinator

    @FocusState private var isFocused: Bool

    // MARK: - Init -

    init(coordinator: OnrampCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 15) {
                Spacer()
                InputContainer(size: .regular) {
                    TextField("Email", text: $coordinator.enteredEmail)
                        .font(.appTextXL)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
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
                    state: coordinator.sendEmailCodeState,
                    style: .filled,
                    title: "Next",
                    disabled: !coordinator.canSendEmailVerification
                ) {
                    isFocused = false
                    coordinator.sendEmailCodeAction()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .dialog(item: $coordinator.dialogItem)
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isFocused.toggle()
        }
    }
}
