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
    @State private var isMovingForward = true
    @Namespace private var animation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return isMovingForward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    var body: some View {
        ZStack {
            switch currentStep {
            case .name:
                CurrencyNameScreen(
                    currencyName: $currencyName,
                    onContinue: { goForward() }
                )
                .transition(stepTransition)

            case .icon:
                CurrencyIconScreen(
                    currencyName: currencyName,
                    selectedImage: $selectedImage,
                    namespace: animation,
                    onContinue: { goForward() }
                )
                .transition(stepTransition)

            case .description:
                CurrencyDescriptionScreen(
                    currencyName: currencyName,
                    selectedImage: selectedImage,
                    currencyDescription: $currencyDescription,
                    namespace: animation,
                    onContinue: { onComplete() }
                )
                .transition(stepTransition)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: goBack)
                    .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .principal) {
                CreationProgressBar(
                    current: currentStep.rawValue + 1,
                    total: CreationProgressBar.totalSteps
                )
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private func goForward() {
        let allSteps = CreationStep.allCases
        guard let index = allSteps.firstIndex(of: currentStep),
              index + 1 < allSteps.count else {
            onComplete()
            return
        }
        dismissKeyboard()
        isMovingForward = true
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
        dismissKeyboard()
        isMovingForward = false
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = allSteps[index - 1]
        }
    }
}

