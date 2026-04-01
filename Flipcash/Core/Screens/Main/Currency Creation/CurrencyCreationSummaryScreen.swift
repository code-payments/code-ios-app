//
//  CurrencyCreationSummaryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyCreationSummaryScreen: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Create Your Currency")
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                Text("Launch your own currency in minutes.\nReady to use right away.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 12)

                CreationStepsList()
                    .padding(.top, 30)

                Spacer()

                NavigationLink(value: CurrencyCreationPath.name) {
                    Text("Get Started")
                }
                .buttonStyle(.filled)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                }
            }
        }
    }
}

// MARK: - CreationStepsList

private struct CreationStepsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepRow(iconName: "textformat", title: "Name", subtitle: "Pick a name for your currency")
            StepRow(iconName: "photo", title: "Icon", subtitle: "Choose an image")
            StepRow(iconName: "pencil.line", title: "Description", subtitle: "Describe your currency")
            StepRow(iconName: "paintbrush.fill", title: "Cash Design", subtitle: "Customize the look")
            StepRow(iconName: "banknote.fill", title: "Purchase $20 USD", subtitle: "Buy the first $20 of your currency", isLast: true)
        }
    }
}

// MARK: - StepRow

private struct StepRow: View {
    let iconName: String
    let title: String
    let subtitle: String
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.15))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: iconName)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.textMain)
                    }

                if !isLast {
                    Rectangle()
                        .fill(Color(white: 0.25))
                        .frame(width: 1, height: 30)
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
            .padding(.top, 12)

            Spacer()
        }
    }
}
