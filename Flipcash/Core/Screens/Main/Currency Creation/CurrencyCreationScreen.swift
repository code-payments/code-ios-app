//
//  CurrencyCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

enum CurrencyCreationPath: Hashable {
    case name
    case icon
    case description
    case billCreation
    case confirmation
}

struct CurrencyCreationScreen: View {
    @State private var path: [CurrencyCreationPath] = []
    @State private var currencyName: String = ""
    @State private var selectedIcon: Int = 0
    @State private var currencyDescription: String = ""
    @State private var backgroundColors: [Color] = [Color(white: 0.1)]
    @Namespace private var animation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            CurrencyCreationSummaryScreen()
                .navigationDestination(for: CurrencyCreationPath.self) { step in
                    switch step {
                    case .name:
                        CurrencyNameScreen(
                            currencyName: $currencyName,
                            namespace: animation
                        )
                    case .icon:
                        PlaceholderScreen(title: "Icon")
                    case .description:
                        PlaceholderScreen(title: "Description")
                    case .billCreation:
                        PlaceholderScreen(title: "Bill Creation")
                    case .confirmation:
                        PlaceholderScreen(title: "Confirmation")
                    }
                }
        }
    }
}

/// Temporary placeholder — replaced screen-by-screen in subsequent tasks.
private struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        Background(color: .backgroundMain) {
            Text(title)
                .font(.appDisplaySmall)
                .foregroundStyle(Color.textMain)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
