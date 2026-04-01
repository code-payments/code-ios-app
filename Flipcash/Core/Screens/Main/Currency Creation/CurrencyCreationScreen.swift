//
//  CurrencyCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

enum CurrencyCreationPath: Hashable {
    case steps
    case billCreation
    case confirmation
}

struct CurrencyCreationScreen: View {
    @State private var path: [CurrencyCreationPath] = []
    @State private var currencyName: String = ""
    @State private var selectedImage: UIImage?
    @State private var currencyDescription: String = ""
    @State private var backgroundColors: [Color] = [Color(white: 0.1)]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            CurrencyCreationSummaryScreen()
                .navigationDestination(for: CurrencyCreationPath.self) { step in
                    switch step {
                    case .steps:
                        CreationStepsContainer(
                            currencyName: $currencyName,
                            selectedImage: $selectedImage,
                            currencyDescription: $currencyDescription,
                            onComplete: { path.append(.billCreation) }
                        )
                    case .billCreation:
                        CurrencyBillCreationScreen(
                            currencyName: currencyName,
                            backgroundColors: $backgroundColors
                        )
                    case .confirmation:
                        CurrencyConfirmationScreen(
                            currencyName: currencyName,
                            backgroundColors: backgroundColors
                        )
                    }
                }
        }
    }
}
