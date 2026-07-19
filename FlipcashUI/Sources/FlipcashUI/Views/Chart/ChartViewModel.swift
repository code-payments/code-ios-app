import SwiftUI

/// Represents the loading state of chart data
public enum ChartLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(ChartError)
}

/// Chart-specific errors
public enum ChartError: Error, Equatable {
    case insufficientData
    case networkError
}

/// ViewModel managing chart state and data
@Observable
public final class ChartViewModel {
    /// Currently selected time range
    public var selectedRange: ChartRange

    /// Data points for the chart
    public var dataPoints: [ChartDataPoint] = []

    /// Currently scrubbed data point (nil when not scrubbing)
    public var scrubbedPoint: ChartDataPoint?

    /// Whether the user is actively scrubbing
    public var isScrubbing: Bool = false

    /// Current loading state
    public var loadingState: ChartLoadingState = .idle

    /// Callback when range changes (caller fetches new data)
    public var onRangeChange: ((ChartRange) -> Void)?

    /// The display value (scrubbed or latest)
    public var displayValue: Double {
        scrubbedPoint?.value ?? currentValue
    }

    /// The display date (scrubbed or latest)
    public var displayDate: Date {
        scrubbedPoint?.date ?? dataPoints.last?.date ?? Date()
    }

    /// Percentage change from first to display value
    public var percentageChange: Double {
        guard let first = dataPoints.first else { return 0 }
        guard first.value != 0 else { return 0 }
        return ((displayValue - first.value) / first.value) * 100
    }

    /// Dollar change from first to display value
    public var valueChange: Double {
        guard let first = dataPoints.first else { return currentValue }
        return displayValue - first.value
    }

    /// Whether the chart shows positive change
    public var isPositive: Bool {
        // Treat sub-cent changes as positive to avoid displaying
        // negligible negative rounding artifacts like "- $0.00".
        guard abs(valueChange) >= 0.01 else { return true }
        return valueChange >= 0
    }
    
    /// A reference to the current value
    public var currentValue: Double

    public init(
        currentValue: Double,
        dataPoints: [ChartDataPoint] = [],
        selectedRange: ChartRange = .all,
        onRangeChange: ((ChartRange) -> Void)? = nil
    ) {
        self.currentValue = currentValue
        self.dataPoints = dataPoints
        self.selectedRange = selectedRange
        self.onRangeChange = onRangeChange
    }

    /// Historical points from the last successful load, kept so a live
    /// current-value tick can re-append without refetching history.
    /// Cleared when a new load starts so a tick mid-load can't repaint a
    /// stale range.
    @ObservationIgnored private var basePoints: [ChartDataPoint] = []

    /// Updates data points and appends currentValue as the final point if different
    public func setDataPoints(_ points: [ChartDataPoint], appendingCurrentValue currentValue: Double) {
        basePoints = points

        var finalPoints = points

        // Append current value as last point if meaningfully different
        if let lastPoint = points.last, abs(lastPoint.value - currentValue) > 0.01 {
            finalPoints.append(ChartDataPoint(
                id: points.count,
                date: Date(),
                value: currentValue,
                normalizedPosition: 1.0
            ))
        }

        self.currentValue = currentValue
        self.dataPoints = finalPoints
        loadingState = .loaded
    }

    /// Replaces the appended "current" point with a fresh live value without
    /// touching fetched history. No-op until a load has succeeded.
    public func updateCurrentValue(_ value: Double) {
        guard !basePoints.isEmpty else { return }
        setDataPoints(basePoints, appendingCurrentValue: value)
    }

    /// Marks the chart as loading
    public func setLoading() {
        basePoints = []
        // Only show loading indicator if we don't already have data
        if dataPoints.isEmpty {
            loadingState = .loading
        }
    }

    /// Sets an error state
    public func setError(_ error: ChartError) {
        loadingState = .error(error)
    }

    /// Retries loading data for the current range
    public func retry() {
        onRangeChange?(selectedRange)
    }

    /// Updates the selected range and notifies caller to fetch new data
    public func selectRange(_ range: ChartRange) {
        guard selectedRange != range else { return }

        // Cancel any ongoing scrub to prevent animation conflicts
        if isScrubbing {
            endScrub()
        }

        selectedRange = range
        onRangeChange?(range)
    }

    /// Finds a data point by its ID
    public func findDataPoint(byId id: Int) -> ChartDataPoint? {
        dataPoints.first { $0.id == id }
    }

    /// Updates the scrubbed point based on a point ID from the chart
    public func updateScrub(pointId: Int) {
        guard let newPoint = findDataPoint(byId: pointId) else { return }

        if !isScrubbing {
            beginScrub()
        }

        // Only update if we changed to a different point
        if scrubbedPoint?.id != newPoint.id {
            scrubbedPoint = newPoint
        }
    }

    /// Ends the scrubbing interaction
    public func endScrub() {
        isScrubbing = false
        scrubbedPoint = nil
    }

    /// Begins the scrubbing interaction
    public func beginScrub() {
        isScrubbing = true
    }
}
