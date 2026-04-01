//
//  CurrencyNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyNameScreen: View {
    @Binding var currencyName: String
    let namespace: Namespace.ID

    @FocusState private var isFocused: Bool

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name Your Currency")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Pick a name for your currency")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)

                InputContainer(highlighted: isFocused) {
                    TextField("Currency Name", text: $currencyName)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                }

                Text(currencyName)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .matchedGeometryEffect(id: "currencyName", in: namespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(currencyName.isEmpty ? 0 : 1)

                Spacer()

                NavigationLink(value: CurrencyCreationPath.icon) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .disabled(currencyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isFocused = true }
    }
}
