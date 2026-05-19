//
//  DepositScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct DepositScreen: View {
    @State private var buttonState: ButtonState = .normal

    private let address: String
    private let name: String?

    init(address: String, name: String?) {
        self.address = address
        self.name = name
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deposit funds into your wallet by sending \(name ?? "funds") to your deposit address below. Tap to copy.")
                    .font(.appTextMedium)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    copyAddress()
                } label: {
                    ImmutableField(address)
                }

                Spacer()

                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: "Copy Address",
                    action: copyAddress
                )
            }
            .padding(20)
        }
        .navigationTitle(name.map { "Deposit \($0)" } ?? "Deposit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        buttonState = .successText("Copied")
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            buttonState = .normal
        }
    }
}
