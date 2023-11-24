//
//  ConfirmPhoneScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-12.
//

import SwiftUI
import CodeUI
import CodeServices
import Introspect

struct ConfirmPhoneScreen: View {
    
    @EnvironmentObject private var notificationController: NotificationController
    
    @Binding private var isActive: Bool
    
    @State private var textField: UITextField?

    @StateObject private var timer = CountdownTimer(seconds: 60)
    
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
            VStack(spacing: 5) {
                Spacer()
                Button {
                    viewModel.isFocused = true
                } label: {
                    ZStack {
                        TwoFactorCodeView(digitCount: viewModel.codeLength, content: $viewModel.enteredCode)
                        TextField("", text: viewModel.adjustingCodeBinding)
                            .foregroundColor(.backgroundMain)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .offset(x: 999999, y: 999999)
                            .introspectTextField { field in
                                textField = field
                            }
                    }
                }
                
                Group {
                    if timer.state == .running {
                        VStack(spacing: 4) {
                            if let phone = viewModel.phone {
                                Text(Localized.Subtitle.smsWasSent)
                                Text(Localized.Subtitle.didntGetCode(phone.national))
                            }
                            Text(Localized.Subtitle.requestNewOneIn(timer.formattedTimeString))
                        }
                        .multilineTextAlignment(.center)
                        
                    } else {
                        VStack(spacing: 4) {
                            Text(Localized.Subtitle.smsWasSent)
                            Button {
                                Task {
                                    let success = try await viewModel.resendCode()
                                    if success {
                                        timer.restart()
                                    }
                                }
                            } label: {
                                Loadable(isLoading: viewModel.isResending, color: .textSecondary) {
                                    Text(Localized.Subtitle.didntGetCodeResend)
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
                    title: Localized.Action.confirm,
                    disabled: !viewModel.isCodeComplete
                ) {
                    viewModel.confirmCode()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .navigationBarTitle(Text(Localized.Title.verifyPhoneNumber), displayMode: .inline)
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
            Analytics.open(screen: .confirmPhone)
            ErrorReporting.breadcrumb(.confirmPhoneScreen)
            timer.start()
            Task {
                try await Task.delay(milliseconds: 600)
                viewModel.isFocused = true
            }
        }
        .onChange(of: viewModel.enteredCode) { _ in
            if viewModel.isCodeComplete {
                viewModel.confirmCode()
            }
        }
        .onChange(of: viewModel.isFocused) { isFocused in
            if isFocused {
                textField?.becomeFirstResponder()
            } else {
                _ = textField?.resignFirstResponder()
            }
        }
        .onChange(of: notificationController.didBecomeActive) { _ in
            viewModel.pasteCodeFromClipboardIfPossible()
        }
    }
}

// MARK: - Previews -

struct ConfirmPhoneScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConfirmPhoneScreen(
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
        .environmentObjectsForSession()
    }
}
