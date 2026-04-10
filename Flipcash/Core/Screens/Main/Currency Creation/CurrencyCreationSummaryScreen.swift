//
//  CurrencyCreationSummaryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyCreationSummaryScreen: View {
    let onGetStarted: () -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 0) {
                Text("Create Your Currency")
                    .font(.appDisplayCompact)
                    .foregroundStyle(Color.textMain)

                Text("Launch your own currency in minutes.\nReady to use right away.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 12)
                    .multilineTextAlignment(.center)

                CreationStepsList()
                    .padding(.top, 45)
                    .padding(.horizontal, 16)

                Spacer()

                Button("Get Started", action: onGetStarted)
                    .buttonStyle(.filled)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - CreationStepsList

private struct CreationStepsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepRow(icon: .CurrencyCreation.name, title: "Name", subtitle: "Pick a name for your currency")
            StepRow(icon: .CurrencyCreation.icon, title: "Icon", subtitle: "Choose an image")
            StepRow(icon: .CurrencyCreation.description, title: "Description", subtitle: "Describe your currency")
            StepRow(icon: .CurrencyCreation.cash, title: "Cash Design", subtitle: "Customize the look")
            StepRow(icon: .CurrencyCreation.purchase, title: "Purchase $20 USD", subtitle: "Buy the first $20 of your currency", isLast: true)
        }
    }
}

// MARK: - StepRow

private struct StepRow: View {
    let icon: ImageResource
    let title: String
    let subtitle: String
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.16))
                    .stroke(.white.opacity(0.1), lineWidth: 1)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(icon)
                            .renderingMode(.template)
                            .foregroundStyle(Color.textMain)
                    }

                if !isLast {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    Gradient.Stop(color: Color(white: 0.45), location: 0.00),
                                    Gradient.Stop(color: Color(red: 0.3, green: 0.3, blue: 0.3), location: 1.00),
                                ],
                                startPoint: UnitPoint(x: 0.5, y: 0),
                                endPoint: UnitPoint(x: 0.5, y: 1)
                            )
                        )
                        .frame(width: 1, height: 45)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)

                Text(subtitle)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
    }
}
