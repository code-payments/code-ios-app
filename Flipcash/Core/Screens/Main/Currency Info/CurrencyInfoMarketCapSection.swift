//
//  CurrencyInfoMarketCapSection.swift
//  Code
//
//  Created by Claude on 2025-02-04.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencyInfoMarketCapSection: View {
    @State private var chartViewModel: ChartViewModel?

    let marketCap: FiatAmount
    let currencyCode: CurrencyCode
    let marketCapController: MarketCapController

    var body: some View {
        VStack(alignment: .leading) {
            Text("Market Cap")
                .foregroundStyle(Color.textSecondary)
                .font(.appTextMedium)
                .padding(.horizontal, 20)

            if let viewModel = chartViewModel {
                StockChart(
                    viewModel: viewModel,
                    currencyCode: currencyCode,
                    positiveColor: .Sentiment.positive,
                    negativeColor: .Sentiment.negative
                )
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .task {
            setupChart()
        }
        .onChange(of: marketCap) { _, newMarketCap in
            guard let viewModel = chartViewModel else { return }
            loadChartData(for: viewModel.selectedRange, into: viewModel)
        }
        .onChange(of: currencyCode) { _, _ in
            guard let viewModel = chartViewModel else { return }
            updateRangeChangeCallback(for: viewModel)
            loadChartData(for: viewModel.selectedRange, into: viewModel)
        }
    }

    private func setupChart() {
        let viewModel = ChartViewModel(currentValue: marketCap.doubleValue, selectedRange: .all)
        chartViewModel = viewModel

        updateRangeChangeCallback(for: viewModel)
        loadChartData(for: .all, into: viewModel)
    }

    private func updateRangeChangeCallback(for viewModel: ChartViewModel) {
        viewModel.onRangeChange = { [weak viewModel] range in
            guard let viewModel else { return }
            loadChartData(for: range, into: viewModel)
        }
    }

    private func loadChartData(for range: ChartRange, into viewModel: ChartViewModel) {
        viewModel.setLoading()
        viewModel.currentValue = marketCap.doubleValue

        Task {
            do {
                let chartPoints = try await marketCapController.fetchChartData(for: range)
                viewModel.setDataPoints(chartPoints, appendingCurrentValue: marketCap.doubleValue)
            } catch let error as ChartError {
                viewModel.setError(error)
            } catch {
                viewModel.setError(.networkError)
            }
        }
    }
}
