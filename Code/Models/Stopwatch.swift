//
//  Stopwatch.swift
//  Code
//
//  Created by Dima Bart on 2021-04-01.
//

import Foundation

typealias TimeProvider = () -> TimeInterval

struct Stopwatch {
    
    typealias Milliseconds = Int
    
    private let time: TimeProvider
    private let start: Double
    
    init(time: @escaping TimeProvider = foundationTime) {
        self.time = time
        self.start = time()
    }
    
    func measure(in units: Unit) -> Milliseconds {
        let milliseconds = Milliseconds((time() - start) * 1000.0)
        switch units {
        case .milliseconds:
            return milliseconds
        case .seconds:
            return milliseconds / 1000
        }
    }
}

extension Stopwatch.Milliseconds {
    func formattedString() -> String {
        String(format: "%0.2f", Double(self) / 1000.0)
    }
}

extension Stopwatch {
    static func foundationTime() -> TimeInterval {
        Date().timeIntervalSince1970
    }
}

extension Stopwatch {
    enum Unit {
        case milliseconds
        case seconds
    }
}
