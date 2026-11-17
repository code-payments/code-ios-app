//
//  ConfirmPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-12.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ConfirmPhoneScreen<VM: PhoneVerifying>: View {

    @Environment(NotificationController.self) private var notificationController
    @State private var countdownEnd: Date?
    @Bindable private var viewModel: VM
    @FocusState private var isFocused: Bool

    private let copy: PhoneVerificationCopy

    // MARK: - Init -

    init(viewModel: VM, copy: PhoneVerificationCopy = .standard) {
        self.viewModel = viewModel
        self.copy = copy
    }

    /// The number the code went to, as the user typed it: country code then national form.
    private var sentToPhone: String {
        guard let phone = viewModel.phone else { return "" }
        return "\(viewModel.countryCode) \(phone.national)"
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: copy == .standard ? .center : .leading, spacing: 5) {
                if let header = copy.codeHeader(phone: sentToPhone, digits: viewModel.codeLength) {
                    OnboardingStepHeader(text: header)
                        .padding(.bottom, 25)
                } else {
                    Spacer()
                }
                Button {
                    isFocused = true
                } label: {
                    ZStack {
                        TwoFactorCodeView(digitCount: viewModel.codeLength, content: $viewModel.enteredCode)
                        TextField("", text: viewModel.adjustingCodeBinding)
                            .foregroundStyle(.backgroundMain)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .offset(x: 999999, y: 999999)
                            .focused($isFocused)
                    }
                }

                if copy == .standard {
                    standardFooter
                } else {
                    stepFooter
                }

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
            .foregroundStyle(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            countdownEnd = Date.now.addingTimeInterval(60)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(100))
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

    // MARK: - Footers -

    /// The on-ramp's centred explanation with the resend line under it.
    private var standardFooter: some View {
        let text = copy.codeExplanation

        return Group {
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
                            try? await viewModel.resendCodeAction()
                            countdownEnd = Date.now.addingTimeInterval(60)
                        }
                    } label: {
                        Loadable(isLoading: viewModel.isResending, color: .textSecondary) {
                            VStack(spacing: 0) {
                                Text(copy.resendTitle)
                                Text(" ") // Offset to match the two line layout above
                            }
                        }
                    }
                }
                .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.textSecondary)
        .font(.appTextSmall)
        .frame(minHeight: 40, alignment: .top)
        .padding(20)
    }

    /// The Group Money step's resend line, then the explanation, both leading.
    private var stepFooter: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let countdownEnd, countdownEnd > .now {
                (Text("Request a new one in ") + Text(timerInterval: .now...countdownEnd, countsDown: true))
                    .contentTransition(.numericText())
                    .font(.appTextSmall)
                    .foregroundStyle(.textSecondary)
            } else {
                Button {
                    resendCode()
                } label: {
                    Loadable(isLoading: viewModel.isResending, color: .textMain) {
                        Text(copy.resendTitle)
                    }
                }
                .font(.appTextSmall)
                .foregroundStyle(.textMain)
            }

            Text(copy.codeExplanation)
                .font(.appTextBody)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private func resendCode() {
        Task {
            try? await viewModel.resendCodeAction()
            countdownEnd = Date.now.addingTimeInterval(60)
        }
    }
}
