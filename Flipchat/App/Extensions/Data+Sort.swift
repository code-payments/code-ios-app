//
//  Data+Sort.swift
//  Code
//
//  Created by Dima Bart on 2024-11-12.
//

import Foundation

extension Data: Comparable {
    
    public static func <(lhs: Data, rhs: Data) -> Bool {
        lhs.lexicographicallyPrecedes(rhs)
    }
    
    public static func == (lhs: Data, rhs: Data) -> Bool {
        lhs.elementsEqual(rhs)
    }
}
