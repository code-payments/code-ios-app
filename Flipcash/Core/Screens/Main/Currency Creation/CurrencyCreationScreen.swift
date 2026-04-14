//
//  CurrencyCreationScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

// MARK: - CreationProgressBar

struct CreationProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        ProgressView(value: Double(current), total: Double(total))
            .progressViewStyle(.linear)
            .tint(Color.textMain)
            .frame(width: 140)
    }
}

// MARK: - CurrencyCreationStep

enum CurrencyCreationStep: Hashable {
    case summary
    case wizard
}

// MARK: - CurrencyCreationState

@MainActor @Observable
final class CurrencyCreationState {
    var currencyName: String = ""
    var selectedImage: UIImage?
    var currencyDescription: String = ""
    var backgroundColors: [Color] = ColorEditorControl.randomColors()
}

// MARK: - CurrencyCreationFlow

/// Attach inside a `NavigationStack` — destinations must be declared at
/// the stack root for `NavigationLink(value:)` calls from pushed steps
/// to resolve.
struct CurrencyCreationFlow: ViewModifier {
    @Bindable var state: CurrencyCreationState

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: CurrencyCreationStep.self) { step in
                switch step {
                case .summary:
                    CurrencyCreationSummaryScreen()
                case .wizard:
                    CurrencyCreationWizardScreen(state: state)
                }
            }
    }
}

extension View {
    func withCurrencyCreationFlow(state: CurrencyCreationState) -> some View {
        modifier(CurrencyCreationFlow(state: state))
    }
}
