//
//  DataPointResamplerTests.swift
//  FlipcashCore
//
//  Created by Claude on 2025-01-23.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("DataPointResampler")
struct DataPointResamplerTests {

    // Simple test point type
    private struct TestPoint: Equatable {
        let x: Double
        let y: Double
    }

    private var resampler: DataPointResampler<TestPoint> {
        DataPointResampler(
            getValue: { $0.y },
            getPosition: { $0.x },
            createPoint: { TestPoint(x: $0, y: $1) }
        )
    }

    // MARK: - Edge Cases

    @Test("Returns original when count equals target")
    func returnsOriginalWhenEqualToTarget() {
        let points = [
            TestPoint(x: 0, y: 10),
            TestPoint(x: 1, y: 20),
            TestPoint(x: 2, y: 30)
        ]

        let result = resampler.resample(points, to: 3)

        #expect(result == points)
    }

    @Test("Returns original for target count of 1")
    func returnsOriginalForTargetOne() {
        let points = [
            TestPoint(x: 0, y: 10),
            TestPoint(x: 1, y: 20)
        ]

        let result = resampler.resample(points, to: 1)

        #expect(result == points)
    }

    @Test("Handles empty array")
    func handlesEmptyArray() {
        let points: [TestPoint] = []

        let result = resampler.resample(points, to: 10)

        #expect(result.isEmpty)
    }

    @Test("Handles single point")
    func handlesSinglePoint() {
        let points = [TestPoint(x: 0, y: 10)]

        let result = resampler.resample(points, to: 10)

        #expect(result.count == 1)
        #expect(result[0] == points[0])
    }

    // MARK: - Downsampling Tests

    @Test("Downsamples to exact target count")
    func downsampleToExactTargetCount() {
        let points = (0..<100).map { TestPoint(x: Double($0), y: Double($0)) }

        let result = resampler.resample(points, to: 20)

        #expect(result.count == 20)
    }

    @Test("Downsampling preserves first point")
    func downsamplingPreservesFirstPoint() {
        let points = (0..<100).map { TestPoint(x: Double($0), y: Double($0) * 2) }

        let result = resampler.resample(points, to: 10)

        #expect(result.first == points.first)
    }

    @Test("Downsampling preserves last point")
    func downsamplingPreservesLastPoint() {
        let points = (0..<100).map { TestPoint(x: Double($0), y: Double($0) * 2) }

        let result = resampler.resample(points, to: 10)

        #expect(result.last == points.last)
    }

    @Test("Downsampling preserves peak in data")
    func downsamplingPreservesPeak() {
        // Data with a clear peak at index 50
        var points: [TestPoint] = []
        for i in 0..<100 {
            let y: Double
            if i < 50 {
                y = Double(i) * 2  // Rising
            } else {
                y = Double(100 - i) * 2  // Falling
            }
            points.append(TestPoint(x: Double(i), y: y))
        }

        let result = resampler.resample(points, to: 10)

        // The peak value (98.0 at x=49 or 50) should be preserved
        let maxValue = result.map(\.y).max()!
        #expect(maxValue >= 96.0)
    }

    @Test("Downsampling preserves valley in data")
    func downsamplingPreservesValley() {
        // Data with a clear valley at index 50
        var points: [TestPoint] = []
        for i in 0..<100 {
            let y: Double
            if i < 50 {
                y = Double(50 - i) * 2  // Falling
            } else {
                y = Double(i - 50) * 2  // Rising
            }
            points.append(TestPoint(x: Double(i), y: y))
        }

        let result = resampler.resample(points, to: 10)

        // The valley value (0.0 at x=50) should be preserved or near
        let minValue = result.map(\.y).min()!
        #expect(minValue <= 4.0)
    }

    @Test("Downsampling maintains monotonic trend for linear data")
    func downsamplingMaintainsMonotonicTrend() {
        // Strictly increasing data
        let points = (0..<100).map { TestPoint(x: Double($0), y: Double($0)) }

        let result = resampler.resample(points, to: 20)

        // Result should still be monotonically increasing
        for i in 1..<result.count {
            #expect(result[i].y >= result[i - 1].y)
        }
    }

    @Test("Downsampling handles large dataset efficiently")
    func downsamplingHandlesLargeDataset() {
        let points = (0..<10000).map { i in
            TestPoint(x: Double(i), y: sin(Double(i) * 0.01) * 100)
        }

        let result = resampler.resample(points, to: 100)

        #expect(result.count == 100)
        #expect(result.first == points.first)
        #expect(result.last == points.last)
    }

    // MARK: - Upsampling Tests

    @Test("Upsamples to exact target count")
    func upsampleToExactTargetCount() {
        let points = [
            TestPoint(x: 0, y: 0),
            TestPoint(x: 10, y: 100)
        ]

        let result = resampler.resample(points, to: 11)

        #expect(result.count == 11)
    }

    @Test("Upsampling preserves first point value")
    func upsamplingPreservesFirstPointValue() {
        let points = [
            TestPoint(x: 0, y: 50),
            TestPoint(x: 100, y: 150)
        ]

        let result = resampler.resample(points, to: 10)

        #expect(result.first?.x == 0)
        #expect(result.first?.y == 50)
    }

    @Test("Upsampling preserves last point value")
    func upsamplingPreservesLastPointValue() {
        let points = [
            TestPoint(x: 0, y: 50),
            TestPoint(x: 100, y: 150)
        ]

        let result = resampler.resample(points, to: 10)

        #expect(result.last?.x == 100)
        #expect(result.last?.y == 150)
    }

    @Test("Upsampling interpolates linearly between two points")
    func upsamplingInterpolatesLinearly() {
        let points = [
            TestPoint(x: 0, y: 0),
            TestPoint(x: 10, y: 100)
        ]

        let result = resampler.resample(points, to: 11)

        // Should have points at x = 0, 1, 2, 3, ..., 10 with y = 0, 10, 20, ..., 100
        for i in 0..<result.count {
            #expect(result[i].x == Double(i), "x at index \(i)")
            #expect(result[i].y == Double(i * 10), "y at index \(i)")
        }
    }

    @Test("Upsampling interpolates correctly with multiple source points")
    func upsamplingInterpolatesWithMultiplePoints() {
        let points = [
            TestPoint(x: 0, y: 0),
            TestPoint(x: 5, y: 50),
            TestPoint(x: 10, y: 100)
        ]

        let result = resampler.resample(points, to: 11)

        #expect(result.count == 11)
        // Midpoint should be interpolated correctly
        #expect(result[5].y == 50)
    }

    @Test("Upsampling handles non-uniform source spacing")
    func upsamplingHandlesNonUniformSpacing() {
        let points = [
            TestPoint(x: 0, y: 0),
            TestPoint(x: 2, y: 20),  // Close together
            TestPoint(x: 10, y: 100) // Far apart
        ]

        let result = resampler.resample(points, to: 11)

        #expect(result.count == 11)
        #expect(result.first?.y == 0)
        #expect(result.last?.y == 100)
    }

    @Test("Upsampling from 10 to 100 produces exact count")
    func upsamplingFrom10To100() {
        // This is the real-world scenario: 1Y has ~10 points, others have ~100
        let points = (0..<10).map { i in
            TestPoint(x: Double(i), y: Double(i) * 10)
        }

        let result = resampler.resample(points, to: 100)

        #expect(result.count == 100)
        #expect(result.first?.y == 0)
        #expect(result.last?.y == 90)
    }

    // MARK: - Consistent Output Count Tests

    @Test("Always outputs exact target count regardless of input size")
    func alwaysOutputsExactTargetCount() {
        let targetCount = 100

        // Test with various input sizes
        let inputSizes = [5, 10, 50, 100, 200, 500]

        for inputSize in inputSizes {
            let points = (0..<inputSize).map { i in
                TestPoint(x: Double(i), y: Double(i))
            }

            let result = resampler.resample(points, to: targetCount)

            #expect(result.count == targetCount, "Input size \(inputSize) should produce \(targetCount) points")
        }
    }

    // MARK: - HistoricalMintDataPoint Extension

    @Test("HistoricalMintDataPoint convenience resampler downsamples")
    func historicalMintDataResamplerDownsamples() {
        let baseDate = Date()
        let points = (0..<50).map { i in
            HistoricalMintDataPoint(
                date: baseDate.addingTimeInterval(Double(i) * 3600),
                marketCap: Double(i) * 1000
            )
        }

        let resampler = DataPointResampler<HistoricalMintDataPoint>.historicalMintData
        let result = resampler.resample(points, to: 10)

        #expect(result.count == 10)
        #expect(result.first?.date == points.first?.date)
        #expect(result.last?.date == points.last?.date)
    }

    @Test("HistoricalMintDataPoint convenience resampler upsamples")
    func historicalMintDataResamplerUpsamples() {
        let baseDate = Date()
        let points = (0..<10).map { i in
            HistoricalMintDataPoint(
                date: baseDate.addingTimeInterval(Double(i) * 3600),
                marketCap: Double(i) * 1000
            )
        }

        let resampler = DataPointResampler<HistoricalMintDataPoint>.historicalMintData
        let result = resampler.resample(points, to: 100)

        #expect(result.count == 100)
        #expect(result.first?.marketCap == 0)
        #expect(result.last?.marketCap == 9000)
    }

    // MARK: - Fill Missing Days Tests

    @Test("fillMissingDays returns original for empty array")
    func fillMissingDaysEmptyArray() {
        let points: [HistoricalMintDataPoint] = []
        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)
        #expect(result.isEmpty)
    }

    @Test("fillMissingDays returns original for single point")
    func fillMissingDaysSinglePoint() {
        let points = [HistoricalMintDataPoint(date: Date(), marketCap: 100)]
        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)
        #expect(result.count == 1)
    }

    @Test("fillMissingDays preserves consecutive days")
    func fillMissingDaysConsecutive() {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())

        let points = (0..<5).map { i in
            HistoricalMintDataPoint(
                date: calendar.date(byAdding: .day, value: i, to: baseDate)!,
                marketCap: Double(i + 1) * 100
            )
        }

        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)

        #expect(result.count == 5)
        for i in 0..<5 {
            #expect(result[i].marketCap == Double(i + 1) * 100)
        }
    }

    @Test("fillMissingDays fills gap with zeros")
    func fillMissingDaysFillsGap() {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())

        // Day 0 and Day 3 have data, Days 1 and 2 are missing
        let points = [
            HistoricalMintDataPoint(
                date: baseDate,
                marketCap: 100
            ),
            HistoricalMintDataPoint(
                date: calendar.date(byAdding: .day, value: 3, to: baseDate)!,
                marketCap: 400
            )
        ]

        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)

        #expect(result.count == 4) // Days 0, 1, 2, 3
        #expect(result[0].marketCap == 100) // Day 0: original
        #expect(result[1].marketCap == 0)   // Day 1: filled with zero
        #expect(result[2].marketCap == 0)   // Day 2: filled with zero
        #expect(result[3].marketCap == 400) // Day 3: original
    }

    @Test("fillMissingDays handles large gap like Dec to Jan")
    func fillMissingDaysLargeGap() {
        let calendar = Calendar.current

        // Simulate the real-world scenario: Dec 27 to Jan 15 (19 days)
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 27
        let dec27 = calendar.date(from: components)!

        components.year = 2026
        components.month = 1
        components.day = 15
        let jan15 = calendar.date(from: components)!

        let points = [
            HistoricalMintDataPoint(date: dec27, marketCap: 0),
            HistoricalMintDataPoint(date: jan15, marketCap: 100)
        ]

        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)

        // Dec 27 to Jan 15 = 20 days inclusive
        #expect(result.count == 20)
        #expect(result.first?.marketCap == 0)  // Dec 27
        #expect(result.last?.marketCap == 100) // Jan 15

        // All days in between should be zero
        for i in 1..<19 {
            #expect(result[i].marketCap == 0, "Day \(i) should be zero")
        }
    }

    @Test("fillMissingDays keeps last value when multiple points on same day with gaps")
    func fillMissingDaysKeepsLastValue() {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())

        // Multiple points on day 0, then a gap, then day 2
        let points = [
            HistoricalMintDataPoint(
                date: baseDate,
                marketCap: 100
            ),
            HistoricalMintDataPoint(
                date: baseDate.addingTimeInterval(3600), // Same day, 1 hour later
                marketCap: 150
            ),
            HistoricalMintDataPoint(
                date: baseDate.addingTimeInterval(7200), // Same day, 2 hours later
                marketCap: 200
            ),
            HistoricalMintDataPoint(
                date: calendar.date(byAdding: .day, value: 2, to: baseDate)!, // Gap: day 1 is missing
                marketCap: 300
            )
        ]

        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)

        #expect(result.count == 3) // Days 0, 1, 2
        #expect(result[0].marketCap == 200) // Last value from day 0
        #expect(result[1].marketCap == 0)   // Day 1: filled with zero
        #expect(result[2].marketCap == 300) // Day 2
    }

    @Test("fillMissingDays preserves intraday data when no gaps")
    func fillMissingDaysPreservesIntradayData() {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())

        // Simulate 1D chart: many points over 2 days with no missing days
        // This mimics 5-minute intervals over ~24 hours
        var points: [HistoricalMintDataPoint] = []
        for i in 0..<289 {
            points.append(HistoricalMintDataPoint(
                date: baseDate.addingTimeInterval(Double(i) * 300), // 5-minute intervals
                marketCap: Double(i) * 10 + Double.random(in: -5...5) // Some variation
            ))
        }

        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)

        // Should return original points unchanged since there are no missing days
        #expect(result.count == 289)
        #expect(result.first?.marketCap == points.first?.marketCap)
        #expect(result.last?.marketCap == points.last?.marketCap)
    }

    @Test("fillMissingDays preserves single day intraday data")
    func fillMissingDaysPreservesSingleDayData() {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: Date())

        // All points within a single day
        let points = (0..<100).map { i in
            HistoricalMintDataPoint(
                date: baseDate.addingTimeInterval(Double(i) * 60), // 1-minute intervals
                marketCap: Double(i) * 5
            )
        }

        let result = DataPointResampler<HistoricalMintDataPoint>.fillMissingDays(points)

        // Should return original points unchanged
        #expect(result.count == 100)
    }
}
