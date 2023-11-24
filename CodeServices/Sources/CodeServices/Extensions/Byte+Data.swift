//
//  Byte+Data.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Array where Element == Byte {
    
    public static func zeroed(with length: Int) -> [Element] {
        [Element](repeating: 0, count: length)
    }
    
    public var data: Data {
        Data(self)
    }
}

extension Data {
    public var bytes: [Byte] {
        [Byte](self)
    }
}
