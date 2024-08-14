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

extension Dictionary {
    static func +(lhs: Dictionary<Key, Value>, rhs: Dictionary<Key, Value>) -> Dictionary<Key, Value> {
        var container: [Key: Value] = [:]
        
        lhs.forEach { key, value in
            container[key] = value
        }
        
        rhs.forEach { key, value in
            container[key] = value
        }
        
        return container
    }
}
