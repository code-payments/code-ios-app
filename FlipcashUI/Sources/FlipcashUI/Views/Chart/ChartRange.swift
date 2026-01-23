import Foundation
import FlipcashCore

/// Time range options for the chart display
public enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case all = "ALL"
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case year = "1Y"
    
    public var id: String { rawValue }
    
    public var title: String { rawValue }
    
    /// Context label for the change description (e.g., "all time", "today")
    public var contextLabel: String {
        switch self {
        case .all: "all time"
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        }
    }
    
    /// Returns the start date for this range from the current date
    public var startDate: Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .all:
            // 5 years back for "all" range
            return calendar.date(byAdding: .year, value: -5, to: now) ?? now
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }
    
    /// Number of data points appropriate for this range
    public var dataPointCount: Int {
        switch self {
        case .all: 120
        case .day: 24
        case .week: 28
        case .month: 30
        case .year: 52
        }
    }

    /// Converts to the API's HistoricalRange type
    public var historicalRange: HistoricalRange {
        switch self {
        case .all: .allTime
        case .day: .lastDay
        case .week: .lastWeek
        case .month: .lastMonth
        case .year: .lastYear
        }
    }
}
