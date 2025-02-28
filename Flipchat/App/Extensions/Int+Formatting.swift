//
//  Int+Formatting.swift
//  Code
//
//  Created by Dima Bart on 2025-02-28.
//

import Foundation

extension Int {
    
    var formattedAbbreviated: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.roundingMode = .halfUp
        
        switch self {
        case 0..<1000:
            formatter.maximumFractionDigits = 0
            return formatter.string(for: self)!
            
        case 1000..<10_000:
            formatter.maximumFractionDigits = 1
            let value = Double(self) / 1000.0
            return "\(formatter.string(for: value)!)k"
            
        case 10_000..<1_000_000:
            formatter.maximumFractionDigits = 1
            let value = Double(self) / 1000.0
            return "\(formatter.string(for: value)!)k"
            
        case 1_000_000...:
            formatter.maximumFractionDigits = 1
            let value = Double(self) / 1_000_000.0
            return "\(formatter.string(for: value)!)M"
            
        default:
            // All cases are covered above
            return "\(self)"
        }
    }
}
