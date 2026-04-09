//
//  ConfirmPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-12.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ConfirmPhoneScreen: View {
    
    @Environment(NotificationController.self) private var notificationController
    @State private var countdownEnd: Date?
    @Bindable private var viewModel: OnrampViewModel
    @FocusState private var isFocused: Bool
    
    // MARK: - Init -
    
    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 5) {
                Spacer()
                Button {
                    isFocused = true
                } label: {
                    ZStack {
                        TwoFactorCodeView(digitCount: viewModel.codeLength, content: $viewModel.enteredCode)
                        TextField("", text: viewModel.adjustingCodeBinding)
                            .foregroundColor(.backgroundMain)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .offset(x: 999999, y: 999999)
                            .focused($isFocused)
                    }
                }
                
                let text = "An SMS message was sent to your phone number with a verification code. Please enter the verification code above."
                
                Group {
                    if let countdownEnd, countdownEnd > .now {
                        VStack(spacing: 15) {
                            Text(text)
                            VStack(spacing: 0) {
                                Text("Didn't get an SMS at \(viewModel.phone?.national ?? "")?")
                                (Text("Request a new one in ") + Text(timerInterval: .now...countdownEnd, countsDown: true))
                                    .contentTransition(.numericText())
                            }
                        }
                        .multilineTextAlignment(.center)
                    } else {
                        VStack(spacing: 15) {
                            Text(text)
                            Button {
                                Task {
                                    do {
                                        try await viewModel.resendCodeAction()
                                        countdownEnd = Date.now.addingTimeInterval(60)
                                    }
                                }
                            } label: {
                                Loadable(isLoading: viewModel.isResending, color: .textSecondary) {
                                    VStack(spacing: 0) {
                                        Text("Didn't get an SMS? Resend")
                                        Text(" ") // Offset to match the two line layout above
                                    }
                                }
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                }
                .foregroundColor(.textSecondary)
                .font(.appTextSmall)
                .frame(minHeight: 40, alignment: .top)
                .padding(20)

                Spacer()
                CodeButton(
                    state: viewModel.confirmCodeButtonState,
                    style: .filled,
                    title: "Confirm",
                    disabled: !viewModel.isCodeComplete
                ) {
                    viewModel.confirmPhoneNumberCodeAction()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .navigationTitle("Verify Phone Number")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            countdownEnd = Date.now.addingTimeInterval(60)
            isFocused = true
        }
        .task(id: countdownEnd) {
            guard let countdownEnd else { return }
            let remaining = countdownEnd.timeIntervalSinceNow
            guard remaining > 0 else {
                self.countdownEnd = nil
                return
            }
            try? await Task.sleep(for: .seconds(remaining))
            if !Task.isCancelled {
                self.countdownEnd = nil
            }
        }
        .onChange(of: viewModel.enteredCode) { _, _ in
            if viewModel.isCodeComplete {
                viewModel.confirmPhoneNumberCodeAction()
            }
        }
        .onChange(of: notificationController.didBecomeActive) { _, _ in
            viewModel.pasteCodeFromClipboardIfPossible()
        }
    }
}
