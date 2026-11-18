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
            Group {
                if let header = copy.codeHeader(phone: sentToPhone, digits: viewModel.codeLength) {
                    // The boxes span the step's width, so they start at the same edge as the
                    // subtitle above and the resend row below.
                    OnboardingStepLayout(header: header) {
                        VStack(alignment: .leading, spacing: OnboardingStepMetrics.formSpacing) {
                            codeField(fillsWidth: true)
                            stepFooter
                        }
                    } action: {
                        confirmButton
                    }
                } else {
                    VStack(spacing: 5) {
                        Spacer()
                        codeField(fillsWidth: false)
                        standardFooter
                        Spacer()
                        confirmButton
                    }
                    .padding(20)
                }
            }
            .foregroundStyle(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            countdownEnd = Date.now.addingTimeInterval(60)
        }
        .focusAfterPush($isFocused)
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

    // MARK: - Subviews -

    private func codeField(fillsWidth: Bool) -> some View {
        Button {
            isFocused = true
        } label: {
            ZStack {
                TwoFactorCodeView(digitCount: viewModel.codeLength, fillsWidth: fillsWidth, content: $viewModel.enteredCode)
                TextField("", text: viewModel.adjustingCodeBinding)
                    .foregroundStyle(.backgroundMain)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .offset(x: 999999, y: 999999)
                    .focused($isFocused)
            }
        }
    }

    private var confirmButton: some View {
        CodeButton(
            state: viewModel.confirmCodeButtonState,
            style: .filled,
            title: copy.codeButtonTitle,
            disabled: !viewModel.isCodeComplete
        ) {
            viewModel.confirmPhoneNumberCodeAction()
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
        VStack(alignment: .leading, spacing: OnboardingStepMetrics.formSpacing) {
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
    }

    private func resendCode() {
        Task {
            try? await viewModel.resendCodeAction()
            countdownEnd = Date.now.addingTimeInterval(60)
        }
    }
}
