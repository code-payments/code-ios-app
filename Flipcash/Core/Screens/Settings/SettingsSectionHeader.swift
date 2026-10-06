//
//  SettingsSectionHeader.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The small grey heading that opens a group of rows on a settings screen.
struct SettingsSectionHeader: View {

    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.appTextHeading)
                .foregroundStyle(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}
