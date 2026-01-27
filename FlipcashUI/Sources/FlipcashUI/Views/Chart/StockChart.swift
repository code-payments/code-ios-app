import SwiftUI

/// A stock-style chart component with scrubbing and range selection
public struct StockChart: View {
    @Bindable private var viewModel: ChartViewModel

    private let positiveColor: Color
    private let negativeColor: Color
    private let valueFormatter: (Double) -> String
    private let dateFormatter: (Date) -> String

    /// Creates a stock chart with externally-provided data via a view model
    /// - Parameters:
    ///   - viewModel: The view model containing chart data and state
    ///   - positiveColor: The chart line color on positive values
    ///   - negativeColor: The chart line color on negative values
    ///   - valueFormatter: Optional custom formatter for displaying values
    ///   - dateFormatter: Optional custom formatter for displaying dates
    public init(
        viewModel: ChartViewModel,
        positiveColor: Color = .green,
        negativeColor: Color = .red,
        valueFormatter: ((Double) -> String)? = nil,
        dateFormatter: ((Date) -> String)? = nil
    ) {
        self.viewModel = viewModel
        self.positiveColor = positiveColor
        self.negativeColor = negativeColor
        self.valueFormatter = valueFormatter ?? { value in
            String(format: "$%.2f", value)
        }
        self.dateFormatter = dateFormatter ?? { date in
            if Calendar.current.isDateInToday(date) {
                return date.formatted(date: .omitted, time: .shortened)
            } else {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
            headerView
                .padding(.horizontal, 20)

            chartView
                .padding(.trailing, 20)

            ChartRangePicker(
                selectedRange: Binding(
                    get: { viewModel.selectedRange },
                    set: { range in
                        withAnimation {
                            viewModel.selectRange(range)
                        }
                    }
                ),
                accentColor: Color(r: 18, g: 42, b: 29)
            )
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(valueFormatter(viewModel.displayValue))
                .foregroundStyle(Color.textMain)
                .font(.appDisplayMedium)
                .contentTransition(.numericText())

            Text(changeText)
                .font(.appTextSmall)
                .fontWeight(.medium)
                .foregroundStyle(viewModel.isScrubbing ? .textSecondary : displayColor)
                .padding(.horizontal, viewModel.isScrubbing ? 0: 6)
                .padding(.vertical, 4)
                .background {
                    if !viewModel.isScrubbing {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(displayColor)
                            .opacity(0.2)
                    }
                }
                .mask {
                    RoundedRectangle(cornerRadius: 4)
                        .transition(.crossFade)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: viewModel.displayValue)
    }

    /// Formatted change text with context (e.g., "+ $17.52 all time")
    /// When scrubbing, shows the date of the selected point instead
    private var changeText: String {
        if viewModel.isScrubbing, let scrubbedPoint = viewModel.scrubbedPoint {
            return dateFormatter(scrubbedPoint.date)
        }

        let change = viewModel.valueChange
        let prefix = change >= 0 ? "+ " : "- "
        let formatted = valueFormatter(abs(change))
        return "\(prefix)\(formatted) \(viewModel.selectedRange.contextLabel)"
    }

    @ViewBuilder
    private var chartView: some View {
        switch viewModel.loadingState {
        case .loading:
            ChartLoadingView()
        case .error(let error):
            ChartErrorView(error: error) { [viewModel] in
                viewModel.retry()
            }
        case .idle, .loaded:
            if viewModel.dataPoints.isEmpty {
                ChartLoadingView()
            } else {
                ChartLineView(
                    dataPoints: viewModel.dataPoints,
                    accentColor: displayColor,
                    secondaryColor: secondaryColor,
                    scrubbedPoint: viewModel.scrubbedPoint,
                    isScrubbing: viewModel.isScrubbing,
                    onScrubChange: { [viewModel] pointId in
                        MainActor.assumeIsolated {
                            viewModel.updateScrub(pointId: pointId)
                        }
                    },
                    onScrubEnd: { [viewModel] in
                        MainActor.assumeIsolated {
                            viewModel.endScrub()
                        }
                    }
                )
                .frame(height: 200)
            }
        }
    }

    // MARK: - Computed Properties

    private var displayColor: Color {
        viewModel.isPositive ? positiveColor : negativeColor
    }

    private var secondaryColor: Color {
        viewModel.isPositive ? Color(r: 17, g: 53, b: 34) : Color(r: 60, g: 37, b: 37)
    }
}

// MARK: - Chart Loading View

private struct ChartLoadingView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.textSecondary)
            Spacer()
        }
        .frame(height: 200)
    }
}

// MARK: - Chart Error View

private struct ChartErrorView: View {
    let error: ChartError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: error == .insufficientData ? "clock" : "chart.line.downtrend.xyaxis")
                .font(.title)
                .foregroundStyle(Color.textSecondary)

            Text(error == .insufficientData ? "Not enough data for this range" : "Unable to load chart")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)

            if error != .insufficientData {
                Button("Retry", action: onRetry)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.actionAlternative)
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
}
