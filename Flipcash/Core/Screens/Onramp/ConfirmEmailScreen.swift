//
//  ConfirmEmailScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-01-12.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ConfirmEmailScreen: View {

    @StateObject private var timer = CountdownTimer(seconds: 60)
    
    @ObservedObject private var viewModel: OnrampViewModel
    
    // MARK: - Init -
    
    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 5) {
                
                Spacer()
                
                // Placeholder to offset the bottom part
                VStack(spacing: 0) {
                    Text(" ")
                    Text(" ")
                }
                .font(.appTextSmall)
                
                Spacer()
                
                VStack(spacing: 30) {
                    Image.asset(.emailSent)
                    
                    Text("Check your inbox")
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                    
                    VStack {
                        Text("Tap the link we sent to")
                            .foregroundStyle(Color.textSecondary)
                        Text(viewModel.enteredEmail)
                            .foregroundStyle(Color.textMain)
                    }
                    .font(.appTextSmall)
                }
                
                Spacer()
                
                Group {
                    if timer.state == .running {
                        VStack(spacing: 0) {
                            Text("Didn't get an email?")
                            Text("Request a new one in \(timer.formattedTimeString)") // <- matching this
                        }
                        .multilineTextAlignment(.center)
                        
                    } else {
                        VStack(spacing: 15) {
                            Button {
                                Task {
                                    do {
                                        try await viewModel.resendEmailCodeAction()
                                    }
                                }
                            } label: {
                                Loadable(isLoading: viewModel.isResending, color: .textSecondary) {
                                    VStack(spacing: 0) {
                                        Text("Didn't get an email? Resend")
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
                    state: viewModel.confirmEmailButtonState,
                    style: .filled,
                    title: "Open Mail",
                    disabled: false
                ) {
                    URL.openMail()
                }
            }
            .padding(20)
            .foregroundColor(.textMain)
        }
        .dialog(item: $viewModel.dialogItem)
        .navigationTitle("Verify Phone Number")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            timer.start()
        }
        .onChange(of: viewModel.isResending) { _, isResending in
            if !isResending {
                Task {
                    timer.restart()
                }
            }
        }
    }
}
