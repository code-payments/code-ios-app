//
//  TutorialChecklistCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A step in a checklist card: what it says, whether it is done, and the glyph
/// it carries while it is not.
///
/// `nonisolated` so its `Equatable`/`Identifiable` refinements stay nonisolated
/// too — this target defaults declarations to the main actor, which would
/// otherwise make every conformance an isolated one.
nonisolated protocol TutorialItemPresentable: Identifiable, Equatable {
    var title: String { get }
    var subtitle: String { get }
    var isCompleted: Bool { get }
    /// The glyph for an unfinished step. A finished one is drawn by the card as
    /// a checkmark, so conformers never describe the completed state.
    ///
    /// Main-actor isolated because `Image.asset(_:)` is, and the glyph is only
    /// ever read while the card renders.
    @MainActor var icon: Image { get }
}

/// A titled checklist of tappable steps with a completed count — the Wallet's
/// "Send Your First Tip" and the You tab's "Finish Your Profile" (Figma node
/// 9544:18140). Completed steps show a green check, dim, and stop responding to
/// taps.
struct TutorialChecklistCard<Item: TutorialItemPresentable>: View {

    let title: String
    let items: [Item]
    let onTap: (Item) -> Void

    private var completedCount: Int { items.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.appBarButton)
                    .foregroundStyle(Color.textMain)
                Spacer()
                Text("\(completedCount)/\(items.count)")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)

            VStack(spacing: 16) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundRow)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
    }

    private func row(_ item: Item) -> some View {
        Button {
            onTap(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                icon(item)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(item.isCompleted ? 0.38 : 1)

                Image.system(.chevronRight)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isCompleted)
    }

    @ViewBuilder private func icon(_ item: Item) -> some View {
        if item.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.Sentiment.positive)
        } else {
            item.icon
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.textSecondary)
        }
    }
}
