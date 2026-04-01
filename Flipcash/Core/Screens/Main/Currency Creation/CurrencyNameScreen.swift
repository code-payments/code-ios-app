//
//  CurrencyNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyNameScreen: View {
    @Binding var currencyName: String
    let namespace: Namespace.ID
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What do you want to call\nyour currency?")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Currency Name", text: $currencyName)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .padding(.top, 20)

                Spacer()

                Button("Next") {
                    onContinue()
                }
                .buttonStyle(.filled)
                .disabled(currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .onAppear { isFocused = true }
    }
}
