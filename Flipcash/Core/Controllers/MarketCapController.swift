//
//  MarketCapController.swift
//  Flipcash
//
//  Created by Raul Riera on 2025-01-26.
//

import Foundation
import FlipcashCore
import FlipcashUI

/// Controller responsible for fetching and processing historical market cap data for charts.
///
/// This controller encapsulates all the logic for:
/// - Fetching historical mint data from the API
/// - Filling gaps in the data (missing days with zero values)
/// - Resampling data to a consistent point count for smooth animations
///
/// ## Usage
///
/// ```swift
/// let controller = MarketCapController(
///     mint: someMint,
///     currencyCode: "USD",
///     client: container.client
/// )
///
/// // Fetch data for a specific range
/// let chartPoints = try await controller.fetchChartData(for: .all)
/// viewModel.setDataPoints(chartPoints)
/// ```
///
/// The controller does not manage any UI state - it only provides processed data.
/// The caller is responsible for managing the `ChartViewModel` state (loading, error, loaded).
final class MarketCapController {

    // MARK: - Constants

    /// The target number of data points for chart display.
    /// This ensures consistent animations regardless of the source data size.
    private static let targetPointCount = 100

    // MARK: - Private Properties

    private let mint: PublicKey
    private let currencyCode: String
    private let client: Client

    // MARK: - Initialization

    /// Creates a new market cap controller.
    ///
    /// - Parameters:
    ///   - mint: The mint public key to fetch historical data for
    ///   - currencyCode: The currency code for value conversion (e.g., "USD")
    ///   - client: The API client for fetching data
    init(mint: PublicKey, currencyCode: String, client: Client) {
        self.mint = mint
        self.currencyCode = currencyCode
        self.client = client
    }

    // MARK: - Public Methods

    /// Fetches and processes historical data for the specified range.
    ///
    /// This method:
    /// 1. Fetches raw data from the API
    /// 2. Fills any missing days with zero values (for multi-day gaps)
    /// 3. Resamples to exactly `targetPointCount` points
    /// 4. Converts to `ChartDataPoint` format with normalized positions
    ///
    /// - Parameter range: The time range to fetch data for
    /// - Returns: Array of `ChartDataPoint` ready for use with `StockChart`
    /// - Throws: `ChartError.insufficientData` if fewer than 2 points returned,
    ///           or network errors from the API
    func fetchChartData(for range: ChartRange) async throws -> [ChartDataPoint] {
        let dataPoints = try await fetchHistoricalData(for: range)
        return processDataPoints(dataPoints)
    }

    // MARK: - Private Methods

    /// Fetches raw historical data from the API.
    ///
    /// - Parameter range: The time range to fetch
    /// - Returns: Array of historical mint data points
    /// - Throws: `ChartError.insufficientData` if fewer than 2 points returned,
    ///           or network errors from the API
    private func fetchHistoricalData(for range: ChartRange) async throws -> [HistoricalMintDataPoint] {
        let dataPoints = try await client.fetchHistoricalMintData(
            mint: mint,
            range: range.historicalRange,
            currencyCode: currencyCode
        )

        // Need at least 2 points to draw a line
        guard dataPoints.count >= 2 else {
            throw ChartError.insufficientData
        }

        return dataPoints
    }

    /// Processes raw data points into chart-ready format.
    ///
    /// Processing steps:
    /// 1. Fill missing days with zeros to prevent incorrect interpolation over gaps
    ///    (only applies when there are actual missing days, not for intraday data)
    /// 2. Resample to exactly `targetPointCount` points for consistent animations
    /// 3. Convert to `ChartDataPoint` with normalized positions (0.0 to 1.0)
    ///
    /// - Parameter dataPoints: Raw historical data points
    /// - Returns: Processed chart data points ready for display
    private func processDataPoints(_ dataPoints: [HistoricalMintDataPoint]) -> [ChartDataPoint] {
        // Fill gaps in multi-day data (preserves intraday detail)
        let filledPoints = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(dataPoints)

        // Resample to consistent count for smooth animations
        let resampler = DataPointResampler<HistoricalMintDataPoint>.historicalMintData
        let sampledPoints = resampler.resample(filledPoints, to: Self.targetPointCount)

        // Convert to chart format with normalized positions
        return sampledPoints.enumerated().map { index, point in
            ChartDataPoint(
                id: index,
                date: point.date,
                value: point.marketCap,
                normalizedPosition: Double(index) / Double(max(sampledPoints.count - 1, 1))
            )
        }
    }
}
