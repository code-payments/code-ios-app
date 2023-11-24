//
//  Data+Slice.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Data {
    func canConsume(_ length: Int) -> Bool {
        count >= length
    }
        
    mutating func consume(_ length: Int) -> Data {
        if length > 0 {
            let data = Data(prefix(length))
            self = Data(suffix(from: Swift.min(length, count)))
            return data
        }
        return Data()
    }
    
    func tail(from index: Int) -> Data {
        if index >= 0 && index < count {
            return Data(suffix(from: index))
        }
        return Data()
    }
    
    func chunk<T>(size: Int, count: Int, block: (Data) -> T) -> [T]? {
        let requestSize = size * count
        
        guard requestSize <= self.count else {
            return nil
        }
        
        var container: [T] = []
        for i in 0..<count {
            let index = i * size
            let slice = subdata(in: index..<index + size)
            container.append(block(slice))
        }
        return container
    }
}
