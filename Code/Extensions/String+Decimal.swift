//
//  String+Decimal.swift
//  Code
//
//  Created by Dima Bart on 2021-02-23.
//

import Foundation

extension String {
    var decimalValue: Decimal? {
        Decimal(string: self)
    }
}
