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
        scrubbedPoint?.value ?? dataPoints.last?.value ?? 0
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
        guard let first = dataPoints.first else { return 0 }
        return displayValue - first.value
    }

    /// Whether the chart shows positive change
    public var isPositive: Bool {
        valueChange >= 0
    }

    public init(
        dataPoints: [ChartDataPoint] = [],
        selectedRange: ChartRange = .all,
        onRangeChange: ((ChartRange) -> Void)? = nil
    ) {
        self.dataPoints = dataPoints
        self.selectedRange = selectedRange
        self.onRangeChange = onRangeChange
    }

    /// Updates the data points from external source
    public func setDataPoints(_ points: [ChartDataPoint]) {
        dataPoints = points
        loadingState = .loaded
    }

    /// Marks the chart as loading
    public func setLoading() {
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
