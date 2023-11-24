//
//  SegmentedControl.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public protocol SegmentedControlItem: Equatable {
    var title: String { get }
}

public struct SegmentedControl<Item>: View where Item: SegmentedControlItem {
    
    @Binding private var selectedItem: Item
    
    private let items: [Item]
    
    public init(items: [Item], selectedItem: Binding<Item>) {
        self.items = items
        self._selectedItem = selectedItem
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.title) { item in
                Button {
                    selectedItem = item
                } label: {
                    Text(item.title)
                        .lineLimit(1)
                        .padding([.top, .bottom], 5)
                        .padding([.leading, .trailing], 10)
                        .background(
                            Rectangle()
                                .fill(item == selectedItem ? Color.chartLine : .clear)
                                .cornerRadius(999)
                        )
                }
                .font(.appTextHeading)
                .foregroundColor(.textMain)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews -

struct SegmentControl_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            SegmentedControl(items: Timeframe.allCases, selectedItem: .constant(.all))
            .padding(10.0)
        }
        .foregroundColor(.textMain)
        .previewLayout(.fixed(width: 290, height: 100))
    }
}

// MARK: - Timeframe -

private enum Timeframe: CaseIterable, SegmentedControlItem {
    
    case day
    case week
    case month
    case month3
    case year
    case all
    
    var title: String {
        switch self {
        case .day:    return "1D"
        case .week:   return "1W"
        case .month:  return "1M"
        case .month3: return "3M"
        case .year:   return "1Y"
        case .all:    return "ALL"
        }
    }
}
