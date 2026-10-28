//
//  OptionCardSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// One card in an ``OptionCardSheet``: a bold title, a grey line under it, and an icon on the right.
struct OptionCard {
    let title: String
    let subtitle: String
    let icon: Image
    let identifier: String
    let action: () -> Void
}

/// A partial sheet of ``ActionCardRow``s, the Group Money sheet's style, with an optional title above
/// the cards. Invite People (node 12844:60) uses it.
///
/// Tapping a card dismisses the sheet before its action runs.
struct OptionCardSheet: View {

    @Environment(\.dismiss) private var dismiss

    var title: String? = nil
    let options: [OptionCard]

    var body: some View {
        PartialSheet {
            OptionCardList(title: title, options: options) { option in
                dismiss()
                option.action()
            }
        }
    }
}

/// The sheet's content, without the sheet, for previews.
struct OptionCardList: View {

    let title: String?
    let options: [OptionCard]
    let onSelect: (OptionCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
            }
            ForEach(options, id: \.identifier) { option in
                card(option)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 20)
    }

    private func card(_ option: OptionCard) -> some View {
        ActionCardRow(icon: option.icon, title: option.title, subtitle: option.subtitle, identifier: option.identifier) {
            onSelect(option)
        }
    }
}
