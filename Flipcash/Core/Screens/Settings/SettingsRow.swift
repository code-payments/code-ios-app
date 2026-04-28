//
//  SettingsRow.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
import FlipcashUI

/// A standard tappable row for settings screens — icon + title + optional badge.
struct SettingsRow: View {

    let image: Image
    let title: String
    let badge: Badge?
    let insets: EdgeInsets
    let action: VoidAction

    init(image: Image, title: String, badge: Badge? = nil, insets: EdgeInsets, action: @escaping VoidAction) {
        self.image = image
        self.title = title
        self.badge = badge
        self.insets = insets
        self.action = action
    }

    init(asset: Asset, title: String, badge: Badge? = nil, insets: EdgeInsets, action: @escaping VoidAction) {
        self.init(image: Image.asset(asset), title: title, badge: badge, insets: insets, action: action)
    }

    init(systemImage: String, title: String, badge: Badge? = nil, insets: EdgeInsets, action: @escaping VoidAction) {
        self.init(image: Image(systemName: systemImage), title: title, badge: badge, insets: insets, action: action)
    }

    var body: some View {
        Row(insets: insets) {
            image.frame(minWidth: 45)
            Text(title)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
            Spacer()
            if let badge {
                badge
            }
        } action: {
            action()
        }
    }
}
