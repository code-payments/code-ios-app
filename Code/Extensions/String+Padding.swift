//
//  String+Padding.swift
//  Code
//
//  Created by Dima Bart on 2021-04-12.
//

import Foundation

extension String {
    func addingLeadingZeros(upTo length: Int) -> String {
        guard count < length else {
            return self
        }
        
        let padding = String(repeating: "0", count: length - count)
        return "\(padding)\(self)"
    }
}
