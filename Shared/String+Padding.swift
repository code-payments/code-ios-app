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

extension String {
    func base64EncodedData() -> Data? {
        var data = Data(utf8)
        let r = data.count % 4
        if r > 0 {
            let requiredPadding = data.count + 4 - r
            let padding = String(repeating: "=", count: requiredPadding)
            data.append(Data(padding.utf8))
        }
        return Data(base64Encoded: data)
    }
}
