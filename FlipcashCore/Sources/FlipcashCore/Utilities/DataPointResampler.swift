//
//  DataPointResampler.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2025-01-23.
//

import Foundation

/// Resamples time-series data points to an exact target count for smooth chart animations.
///
/// - When source has more points than target: Uses LTTB algorithm to downsample while preserving visual characteristics
/// - When source has fewer points than target: Uses linear interpolation to upsample
/// - Always outputs exactly `targetCount` points for consistent animations
public struct DataPointResampler<T> {
    private let getValue: (T) -> Double
    private let getPosition: (T) -> Double
    private let createPoint: (Double, Double) -> T

    /// Creates a resampler for the given data type.
    /// - Parameters:
    ///   - getValue: Extracts the Y-axis value from a data point
    ///   - getPosition: Extracts the X-axis position from a data point (typically time or index)
    ///   - createPoint: Creates a new data point from position and value (for interpolation)
    public init(
        getValue: @escaping (T) -> Double,
        getPosition: @escaping (T) -> Double,
        createPoint: @escaping (Double, Double) -> T
    ) {
        self.getValue = getValue
        self.getPosition = getPosition
        self.createPoint = createPoint
    }

    /// Resamples the data points to exactly the target count.
    ///
    /// - Parameters:
    ///   - points: The original data points
    ///   - targetCount: The exact number of output points
    /// - Returns: Resampled data points with exactly `targetCount` elements
    public func resample(_ points: [T], to targetCount: Int) -> [T] {
        guard targetCount >= 2 else {
            return points
        }

        guard points.count >= 2 else {
            return points
        }

        if points.count > targetCount {
            return downsample(points, to: targetCount)
        } else if points.count < targetCount {
            return upsample(points, to: targetCount)
        } else {
            return points
        }
    }

    // MARK: - Downsampling (LTTB Algorithm)

    /// Downsamples using Largest-Triangle-Three-Buckets algorithm.
    /// Preserves visually significant points like peaks and valleys.
    private func downsample(_ points: [T], to targetCount: Int) -> [T] {
        var result: [T] = []
        result.reserveCapacity(targetCount)

        // Always include first point
        result.append(points[0])

        // Calculate bucket size (excluding first and last points)
        let bucketSize = Double(points.count - 2) / Double(targetCount - 2)

        var previousSelectedIndex = 0

        for i in 0..<(targetCount - 2) {
            // Calculate bucket boundaries
            let bucketStart = Int(Double(i) * bucketSize) + 1
            let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, points.count - 1)

            // Calculate the average point of the next bucket (for triangle calculation)
            let nextBucketStart = bucketEnd
            let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, points.count - 1)

            var avgX: Double = 0
            var avgY: Double = 0
            let nextBucketCount = nextBucketEnd - nextBucketStart

            if nextBucketCount > 0 {
                for j in nextBucketStart..<nextBucketEnd {
                    avgX += getPosition(points[j])
                    avgY += getValue(points[j])
                }
                avgX /= Double(nextBucketCount)
                avgY /= Double(nextBucketCount)
            } else {
                avgX = getPosition(points[points.count - 1])
                avgY = getValue(points[points.count - 1])
            }

            // Find the point in current bucket that creates the largest triangle
            var maxArea: Double = -1
            var selectedIndex = bucketStart

            let pointA = points[previousSelectedIndex]
            let ax = getPosition(pointA)
            let ay = getValue(pointA)

            for j in bucketStart..<bucketEnd {
                let bx = getPosition(points[j])
                let by = getValue(points[j])

                // Calculate triangle area using cross product formula
                let area = abs((ax - avgX) * (by - ay) - (ax - bx) * (avgY - ay))

                if area > maxArea {
                    maxArea = area
                    selectedIndex = j
                }
            }

            result.append(points[selectedIndex])
            previousSelectedIndex = selectedIndex
        }

        // Always include last point
        result.append(points[points.count - 1])

        return result
    }

    // MARK: - Upsampling (Linear Interpolation)

    /// Upsamples using linear interpolation between existing points.
    private func upsample(_ points: [T], to targetCount: Int) -> [T] {
        var result: [T] = []
        result.reserveCapacity(targetCount)

        let firstPosition = getPosition(points[0])
        let lastPosition = getPosition(points[points.count - 1])
        let totalSpan = lastPosition - firstPosition

        for i in 0..<targetCount {
            // Calculate the normalized position (0 to 1) for this output point
            let t = Double(i) / Double(targetCount - 1)
            let targetPosition = firstPosition + t * totalSpan

            // Find the two source points that bracket this position
            let (leftIndex, rightIndex) = findBracketingIndices(for: targetPosition, in: points)

            if leftIndex == rightIndex {
                // Exact match or at boundary
                result.append(points[leftIndex])
            } else {
                // Interpolate between the two points
                let leftPoint = points[leftIndex]
                let rightPoint = points[rightIndex]

                let leftPos = getPosition(leftPoint)
                let rightPos = getPosition(rightPoint)
                let leftVal = getValue(leftPoint)
                let rightVal = getValue(rightPoint)

                // Calculate interpolation factor
                let factor = (targetPosition - leftPos) / (rightPos - leftPos)

                // Linear interpolation
                let interpolatedValue = leftVal + factor * (rightVal - leftVal)

                result.append(createPoint(targetPosition, interpolatedValue))
            }
        }

        return result
    }

    /// Finds the indices of the two points that bracket the target position.
    private func findBracketingIndices(for targetPosition: Double, in points: [T]) -> (Int, Int) {
        // Binary search for efficiency
        var low = 0
        var high = points.count - 1

        while low < high - 1 {
            let mid = (low + high) / 2
            let midPosition = getPosition(points[mid])

            if midPosition <= targetPosition {
                low = mid
            } else {
                high = mid
            }
        }

        return (low, high)
    }
}

// MARK: - Convenience Extension for HistoricalMintDataPoint

extension DataPointResampler where T == HistoricalMintDataPoint {
    /// Creates a resampler configured for HistoricalMintDataPoint
    public static var historicalMintData: DataPointResampler<HistoricalMintDataPoint> {
        DataPointResampler<HistoricalMintDataPoint>(
            getValue: { $0.marketCap },
            getPosition: { $0.date.timeIntervalSince1970 },
            createPoint: { position, value in
                HistoricalMintDataPoint(
                    date: Date(timeIntervalSince1970: position),
                    marketCap: value
                )
            }
        )
    }

    /// Fills gaps in the data by inserting zero-value points for missing days.
    ///
    /// This ensures that gaps in the data (e.g., no data between Dec 27 and Jan 15)
    /// are represented as zero values rather than being interpolated over.
    ///
    /// **Important:** This function only processes data when there are actual missing days.
    /// For intraday data (multiple points per day with no day-level gaps), it returns the
    /// original points unchanged to preserve the detail.
    ///
    /// - Parameter points: The original data points (must be sorted by date)
    /// - Returns: Data points with missing days filled in with zero market cap
    public static func fillMissingDays(_ points: [HistoricalMintDataPoint]) -> [HistoricalMintDataPoint] {
        guard points.count >= 2 else { return points }

        let calendar = Calendar.current

        // Get the date range
        guard let firstDate = points.first?.date,
              let lastDate = points.last?.date,
              let startDay = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: firstDate)),
              let endDay = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: lastDate)) else {
            return points
        }

        // Calculate the expected number of days in the range
        let expectedDayCount = calendar.dateComponents([.day], from: startDay, to: endDay).day! + 1

        // Count unique days in the data
        var uniqueDays = Set<DateComponents>()
        for point in points {
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: point.date)
            uniqueDays.insert(dayComponents)
        }

        // If there are no missing days, return original points unchanged
        // This preserves intraday detail (e.g., 289 points over 2 days)
        if uniqueDays.count == expectedDayCount {
            return points
        }

        // There are missing days - aggregate by day and fill gaps
        var result: [HistoricalMintDataPoint] = []

        // Group points by day, keeping the last value for each day
        var pointsByDay: [DateComponents: HistoricalMintDataPoint] = [:]
        for point in points {
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: point.date)
            // Keep the last (most recent) point for each day
            pointsByDay[dayComponents] = point
        }

        // Iterate through each day in the range
        var currentDay = startDay
        while currentDay <= endDay {
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: currentDay)

            if let existingPoint = pointsByDay[dayComponents] {
                result.append(existingPoint)
            } else {
                // Fill missing day with zero
                result.append(HistoricalMintDataPoint(date: currentDay, marketCap: 0))
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) else { break }
            currentDay = nextDay
        }

        return result
    }
}
