import SwiftUI

/// Segmented picker for selecting chart time ranges
public struct ChartRangePicker: View {
    @Binding var selectedRange: ChartRange
    let accentColor: Color
    
    @Namespace private var animation
    
    public init(selectedRange: Binding<ChartRange>, accentColor: Color) {
        self._selectedRange = selectedRange
        self.accentColor = accentColor
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(ChartRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.appTextMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedRange == range ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selectedRange == range {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(accentColor)
                                    .matchedGeometryEffect(id: "selection", in: animation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var range: ChartRange = .all
        
        var body: some View {
            ChartRangePicker(selectedRange: $range, accentColor: .green)
        }
    }
    
    return PreviewWrapper()
        .padding()
}
