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
        ListSectionTitle(title)
    }
}
