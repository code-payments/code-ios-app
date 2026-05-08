//
//  SettingsAutoReturnScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-08.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SettingsAutoReturnScreen: View {

    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Background(color: .backgroundMain) {
            List {
                Section(footer: AutoReturnFooter()) {
                    ForEach(AutoReturnTimeout.allCases, id: \.self) { option in
                        AutoReturnTimeoutRow(
                            option: option,
                            selection: $preferences.autoReturnTimeout
                        )
                    }
                }
                .listRowSeparatorTint(Color.rowSeparator)
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Auto-Return")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Color.textMain)
    }
}

private struct AutoReturnFooter: View {
    var body: some View {
        Text("Return to the Scanner if the app has been in the background for longer than the selected duration.")
    }
}

private struct AutoReturnTimeoutRow: View {

    let option: AutoReturnTimeout
    @Binding var selection: AutoReturnTimeout

    var body: some View {
        Button {
            withAnimation { selection = option }
        } label: {
            HStack {
                Text(option.displayName)
                    .foregroundStyle(.textMain)
                    .font(.appTextMedium)
                Spacer()
                CheckView(active: selection == option)
            }
            .padding(.vertical, 12)
            .background(Color.backgroundMain)
        }
        .listRowBackground(Color.backgroundMain)
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == option ? [.isSelected] : [])
    }
}
