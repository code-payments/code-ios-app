import Foundation

/// A single data point for the chart
public struct ChartDataPoint: Identifiable, Equatable, Sendable {
    public let id: Int
    public let date: Date
    public let value: Double
    /// Normalized position (0-1) for smooth animations between different time ranges
    public let normalizedPosition: Double
    
    public init(id: Int, date: Date, value: Double, normalizedPosition: Double) {
        self.id = id
        self.date = date
        self.value = value
        self.normalizedPosition = normalizedPosition
    }
}
