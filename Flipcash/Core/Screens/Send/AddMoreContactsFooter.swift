//
//  AddMoreContactsFooter.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Footer under the populated recipient list in iOS 18 limited access. Routes to
/// Settings to share more contacts — adding them in-app is unavailable on
/// iOS 26 (FB14821786).
struct AddMoreContactsFooter: View {

    var body: some View {
        Button {
            URL.openSettings()
        } label: {
            HStack(spacing: 12) {
                StackedPeopleIcon()

                Text("Add More Contacts")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)

                Spacer()

                // Decorative — the whole row is the tap target, like the
                // contact rows' "Invite" pill.
                Text("Settings")
                    .chip(.prominent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddMoreContactsFooter()
        .padding()
        .background(Color.backgroundMain)
}
