//
//  SettingsToggle.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI

struct SettingsToggle: View {

    let image: Image
    let title: String
    let isEnabled: Binding<Bool>
    let insets: EdgeInsets

    init(image: Image, title: String, isEnabled: Binding<Bool>, insets: EdgeInsets = EdgeInsets(top: 25, leading: 0, bottom: 25, trailing: 0)) {
        self.image = image
        self.title = title
        self.isEnabled = isEnabled
        self.insets = insets
    }

    var body: some View {
        Row(insets: insets) {
            image.frame(minWidth: 45)
            Toggle(title, isOn: isEnabled)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .padding(.trailing, 2)
                .tint(.textSuccess)
        }
    }
}
