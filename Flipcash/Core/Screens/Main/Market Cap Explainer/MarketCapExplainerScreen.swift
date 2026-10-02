//
//  MarketCapExplainerScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// "How Market Cap Works": drag the community's purchases along the curve and
/// see what the balance would be worth.
struct MarketCapExplainerScreen: View {

    @State private var viewModel: MarketCapExplainerViewModel

    init(mint: PublicKey, session: Session, ratesController: RatesController) {
        _viewModel = State(initialValue: MarketCapExplainerViewModel(
            mint: mint,
            session: session,
            ratesController: ratesController
        ))
    }

    var body: some View {
        Background(color: .backgroundMain) {
            switch viewModel.loadingState {
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.textSecondary)
            case .unavailable:
                Text("Unable to load")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            case .loaded(let name, let explainer):
                MarketCapExplainerContent(
                    name: name,
                    explainer: explainer,
                    viewModel: viewModel
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

// MARK: - Content -

struct MarketCapExplainerContent: View {
    let name: String
    let explainer: MarketCapExplainer
    @Bindable var viewModel: MarketCapExplainerViewModel

    private var selection: MarketCapExplainer.Stop {
        viewModel.selection ?? explainer.todayStop
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("The more people buy \(name), the more valuable \(name) becomes.")
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .accessibilityAddTraits(.isHeader)

                heroCard

                if explainer.heldQuarks != nil {
                    ownershipCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Amount of \(name) purchased by the community")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                Text(viewModel.reserveText(selection.reserve))
                    .font(.appDisplayCompact)
                    .foregroundStyle(Color.textMain)
                    .contentTransition(.numericText())
                    .animation(.default, value: viewModel.reserveText(selection.reserve))
            }

            MarketCapCurveChart(
                explainer: explainer,
                position: viewModel.trackPosition,
                reserveText: viewModel.reserveText
            )

            MarketCapSlider(position: $viewModel.trackPosition, ticks: ticks)

            if explainer.heldQuarks != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your \(name) balance would be worth")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    Text(viewModel.worthText(at: selection))
                        .font(.appDisplayMedium)
                        .foregroundStyle(Color.textMain)
                        .contentTransition(.numericText())
                        .animation(.default, value: viewModel.worthText(at: selection))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundRow)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }

    private var ticks: [MarketCapSlider.Tick] {
        explainer.stops.map { stop in
            MarketCapSlider.Tick(
                id: stop.reserve,
                position: explainer.trackPosition(of: stop),
                label: stop.isToday
                    ? "Today"
                    : viewModel.reserveText(stop.reserve),
                isToday: stop.isToday
            )
        }
    }

    // MARK: - Ownership

    private var ownershipCard: some View {
        let ownership = explainer.ownership
        return VStack(alignment: .leading, spacing: 0) {
            Text("Your Ownership")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .padding(.bottom, 12)

            row("Underlying tokens you own", viewModel.tokensText(ownership.tokens))
            row("Current price per token", viewModel.priceText(ownership.price))
            row("Share of circulating supply", viewModel.percentText(ownership.shareOfCirculating))
            row("Share of max supply", viewModel.percentText(ownership.shareOfMax))
            row(
                "Your current appreciation",
                viewModel.appreciationText,
                valueColor: appreciationColor
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundRow)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }

    private var appreciationColor: Color {
        switch viewModel.appreciationSign {
        case .positive: MarketCapExplainerPalette.green
        case .negative: MarketCapExplainerPalette.red
        case .zero: Color.textMain
        }
    }

    private func row(_ title: String, _ value: String, valueColor: Color = .textMain) -> some View {
        HStack {
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.appTextMedium)
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 10)
    }
}
