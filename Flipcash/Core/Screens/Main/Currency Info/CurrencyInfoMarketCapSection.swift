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
    /// Points that arrived before the host was ready to draw them.
    @State private var pendingPoints: [ChartDataPoint]?

    let marketCap: FiatAmount
    let currencyCode: CurrencyCode
    let marketCapController: MarketCapController
    /// Gates the chart's *data* only. The section itself — its value, the
    /// all-time change, and the range picker — renders immediately around a
    /// reserved 200pt plot area, so the page arrives complete and in its final
    /// layout. Drawing an actual populated Swift Charts plot is the expensive
    /// part, and the host holds that back until the opening animation is done.
    var isReady: Bool = true

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
        // The view model is cheap and gives the section its full height right
        // away: value, change, a placeholder plot, and the range picker. The
        // fetch starts here too — it is network-bound, so it costs an opening
        // animation nothing, and starting it only once the transition had
        // finished left the section sitting visibly empty afterwards while it
        // ran. `isReady` gates the *drawing* of the result instead.
        .task {
            guard chartViewModel == nil else { return }
            setupChart()
            await loadInitialChartData()
        }
        // Draw whatever the fetch already returned, now that it is safe to.
        .task(id: isReady) {
            guard isReady, let points = pendingPoints, let viewModel = chartViewModel else { return }
            pendingPoints = nil
            viewModel.setDataPoints(points, appendingCurrentValue: marketCap.doubleValue)
        }
        .onChange(of: marketCap) { _, newMarketCap in
            // Live ticks only move the appended "current" point — history
            // doesn't change when the spot value moves, so no refetch.
            chartViewModel?.updateCurrentValue(newMarketCap.doubleValue)
        }
        .onChange(of: currencyCode) { _, _ in
            guard let viewModel = chartViewModel else { return }
            updateRangeChangeCallback(for: viewModel)
            loadChartData(for: viewModel.selectedRange, into: viewModel)
        }
    }

    /// The opening fetch. Runs immediately, but holds its points back until the
    /// host is ready — populating a Swift Charts plot is the expensive part of
    /// this screen, and doing it mid-animation drops frames.
    private func loadInitialChartData() async {
        guard let viewModel = chartViewModel else { return }
        do {
            let points = try await marketCapController.fetchChartData(for: .all)
            if isReady {
                viewModel.setDataPoints(points, appendingCurrentValue: marketCap.doubleValue)
            } else {
                pendingPoints = points
            }
        } catch let error as ChartError {
            viewModel.setError(error)
        } catch {
            viewModel.setError(.networkError)
        }
    }

    private func setupChart() {
        let viewModel = ChartViewModel(currentValue: marketCap.doubleValue, selectedRange: .all)
        viewModel.setLoading()
        chartViewModel = viewModel

        updateRangeChangeCallback(for: viewModel)
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
