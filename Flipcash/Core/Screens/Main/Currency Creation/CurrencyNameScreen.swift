//
//  CurrencyNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyNameScreen: View {
    @Binding var currencyName: String
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    private let characterLimit = 25

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What do you want to call\nyour currency?")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Currency Name", text: $currencyName)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .padding(.top, 20)
                    .onChange(of: currencyName) { _, newValue in
                        if newValue.count > characterLimit {
                            currencyName = String(newValue.prefix(characterLimit))
                        }
                    }

                Spacer()

                Text("\(characterLimit - currencyName.count) characters")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 12)

                Button("Next", action: onContinue)
                    .buttonStyle(.filled)
                    .disabled(currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .onAppear { isFocused = true }
    }
}
