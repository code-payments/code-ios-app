//
//  NumberFormatter+Formats.swift
//  Code
//
//  Created by Dima Bart on 2024-11-01.
//

import Foundation

extension NumberFormatter {
    public static let roomNumber: NumberFormatter = {
        let prefix = "#"
        let f = NumberFormatter()
        f.numberStyle = .none
        f.positivePrefix = prefix
        f.negativePrefix = prefix
        return f
    }()
}
