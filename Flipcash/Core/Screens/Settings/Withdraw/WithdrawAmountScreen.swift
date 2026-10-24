//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawAmountScreen: View {

    let title: String
    @Binding var enteredAmount: String
    let subtitle: EnterAmountView.Subtitle
    let canProceed: Bool
    let onProceed: () -> Void

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .withdraw,
                enteredAmount: $enteredAmount,
                subtitle: subtitle,
                actionState: .constant(.normal),
                actionEnabled: { _ in canProceed },
                action: onProceed
            )
            .foregroundStyle(Color.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }
}
