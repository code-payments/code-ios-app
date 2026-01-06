import SwiftUI

/// ViewModel managing chart state and data generation
@MainActor
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
    
    /// Start value for random data generation
    public let startValue: Double
    
    /// End value for random data generation
    public let endValue: Double
    
    /// The display value (scrubbed or latest)
    public var displayValue: Double {
        scrubbedPoint?.value ?? dataPoints.last?.value ?? endValue
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
        startValue: Double,
        endValue: Double,
        selectedRange: ChartRange = .all
    ) {
        self.startValue = startValue
        self.endValue = endValue
        self.selectedRange = selectedRange
        
        generateData()
    }
    
    /// Generates random data points between start and end values
    public func generateData() {
        let count = selectedRange.dataPointCount
        let startDate = selectedRange.startDate
        let endDate = Date()
        
        let timeInterval = endDate.timeIntervalSince(startDate)
        let step = timeInterval / Double(count - 1)
        
        var points: [ChartDataPoint] = []
        var currentValue = startValue
        let targetValue = endValue
        
        // Calculate the trend needed to reach target
        let trendPerStep = (targetValue - startValue) / Double(count - 1)
        
        for i in 0..<count {
            let date = startDate.addingTimeInterval(step * Double(i))
            
            // Add randomness while following the trend
            let noise = Double.random(in: -0.05...0.05) * abs(endValue - startValue)
            let trendValue = startValue + (trendPerStep * Double(i))
            currentValue = trendValue + noise
            
            // Ensure we hit the exact end value on the last point
            if i == count - 1 {
                currentValue = targetValue
            }
            
            points.append(ChartDataPoint(date: date, value: currentValue))
        }
        
        dataPoints = points
    }
    
    /// Updates the selected range and regenerates data
    public func selectRange(_ range: ChartRange) {
        guard selectedRange != range else { return }
        
        // Cancel any ongoing scrub to prevent animation conflicts
        if isScrubbing {
            endScrub()
        }
        
        selectedRange = range
        generateData()
    }
    
    /// Finds the nearest data point to the given date
    public func findDataPoint(nearestTo date: Date) -> ChartDataPoint? {
        guard !dataPoints.isEmpty else { return nil }
        
        return dataPoints.min(by: { point1, point2 in
            abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
        })
    }
    
    /// Updates the scrubbed point based on a date from chart proxy
    public func updateScrub(for date: Date) {
        guard let newPoint = findDataPoint(nearestTo: date) else { return }
        
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
