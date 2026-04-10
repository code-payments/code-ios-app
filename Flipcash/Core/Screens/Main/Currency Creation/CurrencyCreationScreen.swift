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

    /// Name, Icon, Description, Bill Creation, Confirmation
    static let totalSteps = 5

    var body: some View {
        ProgressView(value: Double(current), total: Double(total))
            .progressViewStyle(.linear)
            .tint(Color.textMain)
            .frame(width: 140)
    }
}

struct CurrencyCreationScreen: View {
    @State private var currencyName: String = ""
    @State private var selectedImage: UIImage?
    @State private var currencyDescription: String = ""
    @State private var backgroundColors: [Color] = [Color(white: 0.1)]
    @State private var showSteps = false
    @State private var showBillCreation = false
    @State private var showConfirmation = false

    var body: some View {
        CurrencyCreationSummaryScreen(onGetStarted: { showSteps = true })
            .navigationDestination(isPresented: $showSteps) {
                CreationStepsContainer(
                    currencyName: $currencyName,
                    selectedImage: $selectedImage,
                    currencyDescription: $currencyDescription,
                    onComplete: { showBillCreation = true }
                )
                .navigationDestination(isPresented: $showBillCreation) {
                    CurrencyBillCreationScreen(
                        currencyName: currencyName,
                        backgroundColors: $backgroundColors,
                        onContinue: { showConfirmation = true }
                    )
                    .navigationDestination(isPresented: $showConfirmation) {
                        CurrencyConfirmationScreen(
                            currencyName: currencyName,
                            selectedImage: selectedImage,
                            backgroundColors: $backgroundColors
                        )
                    }
                }
            }
    }
}
