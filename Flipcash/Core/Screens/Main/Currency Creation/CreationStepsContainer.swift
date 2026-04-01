//
//  CreationStepsContainer.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

enum CreationStep: Int, CaseIterable {
    case name
    case icon
    case description
}

struct CreationStepsContainer: View {
    @Binding var currencyName: String
    @Binding var selectedImage: UIImage?
    @Binding var currencyDescription: String
    let onComplete: () -> Void

    @State private var currentStep: CreationStep = .name
    @Namespace private var animation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            switch currentStep {
            case .name:
                CurrencyNameScreen(
                    currencyName: $currencyName,
                    namespace: animation,
                    onContinue: { goForward() }
                )
                .transition(.move(edge: .leading))

            case .icon:
                CurrencyIconScreen(
                    currencyName: currencyName,
                    selectedImage: $selectedImage,
                    namespace: animation,
                    onContinue: { goForward() }
                )
                .transition(.move(edge: .trailing))

            case .description:
                CurrencyDescriptionScreen(
                    currencyName: currencyName,
                    selectedImage: selectedImage,
                    currencyDescription: $currencyDescription,
                    namespace: animation,
                    onContinue: { onComplete() }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .principal) {
                ProgressView(
                    value: Double(currentStep.rawValue + 1),
                    total: Double(CreationStep.allCases.count)
                )
                .progressViewStyle(.linear)
                .tint(Color.textMain)
                .frame(width: 140)
            }
        }
    }

    private func goForward() {
        let allSteps = CreationStep.allCases
        guard let index = allSteps.firstIndex(of: currentStep),
              index + 1 < allSteps.count else {
            onComplete()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = allSteps[index + 1]
        }
    }

    private func goBack() {
        let allSteps = CreationStep.allCases
        guard let index = allSteps.firstIndex(of: currentStep), index > 0 else {
            dismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = allSteps[index - 1]
        }
    }
}

