//
//  CurrencyCreationSummaryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyCreationSummaryScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    private var purchaseAmount: ExchangedFiat {
        let quarks = session.userFlags?.newCurrencyPurchaseAmount.quarks ?? 0
        return ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarks, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: 0
        )
    }

    private var feeAmount: ExchangedFiat {
        let quarks = session.userFlags?.newCurrencyFeeAmount.quarks ?? 0
        return ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: quarks, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: 0
        )
    }

    private var totalLaunchCost: ExchangedFiat {
        purchaseAmount.adding(feeAmount)
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .center, spacing: 0) {
                Text("Launch your own currency in minutes.\nReady to use right away.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                CreationStepsList(
                    totalCost: totalLaunchCost.nativeAmount.formatted(),
                    purchaseAmount: purchaseAmount.nativeAmount.formatted()
                )
                    .padding(.top, 45)

                Spacer()

                Button("Get Started") {
                    router.push(.currencyCreationWizard)
                }
                .buttonStyle(.filled)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Create Your Currency")
    }
}

// MARK: - CreationStepsList

private struct CreationStepsList: View {
    let totalCost: String
    let purchaseAmount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepRow(icon: .CurrencyCreation.name, title: "Name", subtitle: "Pick a name for your currency")
            StepRow(icon: .CurrencyCreation.icon, title: "Icon", subtitle: "Choose an image")
            StepRow(icon: .CurrencyCreation.description, title: "Description", subtitle: "Describe your currency")
            StepRow(icon: .CurrencyCreation.cash, title: "Cash Design", subtitle: "Customize the look")
            StepRow(
                icon: .CurrencyCreation.purchase,
                title: "Pay \(totalCost) USD Fee",
                subtitle: "Pay to create your currency"
            )
            StepRow(
                icon: .CurrencyCreation.gift,
                title: "Limited Time: Get \(purchaseAmount) Free",
                subtitle: "Get the first \(purchaseAmount) of your currency",
                isLast: true
            )
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
                                    Gradient.Stop(color: .white, location: 0.00),
                                    Gradient.Stop(color: Color(red: 0.3, green: 0.3, blue: 0.3), location: 1.00),
                                ],
                                startPoint: UnitPoint(x: 0.5, y: 0),
                                endPoint: UnitPoint(x: 0.5, y: 1)
                            )
                        )
                        .opacity(0.16)
                        .frame(width: 2, height: 42)
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
        }
    }
}
