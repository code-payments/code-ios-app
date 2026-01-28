//
//  ValueAppreciation.swift
//  FlipcashUI
//
//  Created by Raul Riera on 2026-01-28.
//

import SwiftUI
import FlipcashCore

public struct ValueAppreciation: View {
    public let amount: Quarks
    public let isPositive: Bool
    
    public init(amount: Quarks, isPositive: Bool) {
        self.amount = amount
        self.isPositive = isPositive
    }
    
    public var body: some View {
        let prefix = isPositive ? "+" : "-"
        
        HStack {
            Text("\(prefix)\(amount.formatted())")
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPositive ? .actionAlternative : Color(r: 228, g: 42, b: 42))
                        .opacity(0.2)
                }
            if isPositive {
                Text("from currency appreciation")
            } else {
                Text("from currency depreciation")
            }
        }
            .font(.appTextSmall)
            .foregroundStyle(isPositive ? .actionAlternative : Color(r: 228, g: 42, b: 42))
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
    }
}
