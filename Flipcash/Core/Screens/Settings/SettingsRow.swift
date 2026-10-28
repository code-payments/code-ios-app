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

    init(icon: Icon, title: String, badge: Badge? = nil, insets: EdgeInsets, action: @escaping VoidAction) {
        self.init(image: Image.icon(icon), title: title, badge: badge, insets: insets, action: action)
    }

    var body: some View {
        ListRow(title, tone: tone, showsDivider: showsDivider, action: action) {
            ListRowIcon(image)
        } trailing: {
            HStack(spacing: 8) {
                if let badge {
                    badge
                }
                if showsChevron {
                    ListRowChevron()
                }
            }
        }
    }

    // Rows v2 exploration: set per call site without widening every initializer.
    private var tone: ListRowTone { isDestructive ? .destructive : .standard }
    var showsDivider = true
    var showsChevron = true
    var isDestructive = false

    /// Hides the divider, for the last row of a section.
    func lastInSection() -> Self { var copy = self; copy.showsDivider = false; return copy }

    /// Drops the chevron, for a row that acts in place instead of pushing.
    func actsInPlace() -> Self { var copy = self; copy.showsChevron = false; return copy }

    /// Draws the title and icon in the error colour, for a destructive action.
    func destructive() -> Self { var copy = self; copy.isDestructive = true; return copy }
}

extension Badge {
    /// The "Beta" pill shown on settings rows that gate beta features.
    static let beta = Badge(decoration: .circle(.textWarning), text: "Beta")
}
