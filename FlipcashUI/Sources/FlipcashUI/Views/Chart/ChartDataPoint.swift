import Foundation

/// A single data point for the chart
public struct ChartDataPoint: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let value: Double
    
    public init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}
