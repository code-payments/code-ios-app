//
//  CurrencyIconScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// Placeholder icon names used across the creation flow.
/// The user will replace these with real assets later.
enum CurrencyCreationIcons {
    static let placeholders = ["star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill", "diamond.fill", "crown.fill", "globe"]

    static func name(for index: Int) -> String {
        placeholders[index % placeholders.count]
    }
}

struct CurrencyIconScreen: View {
    let currencyName: String
    @Binding var selectedIcon: Int
    let namespace: Namespace.ID

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 20) {
                // Geometry-matched currency name
                Text(currencyName)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .matchedGeometryEffect(id: "currencyName", in: namespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose an Icon")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Select an image for your currency")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Placeholder icon grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<8, id: \.self) { index in
                        IconTile(
                            index: index,
                            iconName: CurrencyCreationIcons.name(for: index),
                            isSelected: selectedIcon == index,
                            namespace: namespace,
                            onSelect: { selectedIcon = index }
                        )
                    }
                }

                Spacer()

                NavigationLink(value: CurrencyCreationPath.description) {
                    Text("Continue")
                }
                .buttonStyle(.filled)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - IconTile

private struct IconTile: View {
    let index: Int
    let iconName: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.15))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: iconName)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.textMain)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(
            id: isSelected ? "currencyIcon" : "icon-\(index)",
            in: namespace
        )
    }
}
