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

    @State private var countdownEnd: Date?

    @Bindable private var onrampCoordinator: OnrampCoordinator

    // MARK: - Init -

    init(onrampCoordinator: OnrampCoordinator) {
        self.onrampCoordinator = onrampCoordinator
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
                        Text(onrampCoordinator.enteredEmail)
                            .foregroundStyle(Color.textMain)
                    }
                    .font(.appTextSmall)
                }

                Spacer()

                Group {
                    if let countdownEnd, countdownEnd > .now {
                        VStack(spacing: 0) {
                            Text("Didn't get an email?")
                            (Text("Request a new one in ") + Text(timerInterval: .now...countdownEnd, countsDown: true))
                                .contentTransition(.numericText())
                        }
                        .multilineTextAlignment(.center)
                    } else {
                        VStack(spacing: 15) {
                            Button {
                                Task {
                                    do {
                                        try await onrampCoordinator.resendEmailCodeAction()
                                    }
                                }
                            } label: {
                                Loadable(isLoading: onrampCoordinator.isResending, color: .textSecondary) {
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
                    state: onrampCoordinator.confirmEmailButtonState,
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
        .dialog(item: $onrampCoordinator.dialogItem)
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            countdownEnd = Date.now.addingTimeInterval(60)
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
        .onChange(of: onrampCoordinator.isResending) { _, isResending in
            if !isResending {
                countdownEnd = Date.now.addingTimeInterval(60)
            }
        }
    }
}
