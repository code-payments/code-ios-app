//
//  Abacus.swift
//  Code
//
//  Created by Dima Bart on 2023-06-26.
//

import Foundation

@MainActor
final class Abacus: ObservableObject {
    
    private var container: [Name: Stopwatch] = [:]
    
    // MARK: - Init -
    
    init() {
        
    }
    
    func start(_ name: Name, time: TimeProvider? = nil) {
        container[name] = Stopwatch(time: time ?? Stopwatch.foundationTime)
    }
    
    func isTracking(_ name: Name) -> Bool {
        snapshot(name) != nil
    }
    
    func snapshot(_ name: Name) -> Stopwatch? {
        container[name]
    }
    
    func end(_ name: Name) -> Stopwatch? {
        container.removeValue(forKey: name)
    }
}

extension Abacus {
    enum Name: Hashable, Equatable {
        case grabTime
        case cashLinkGrabTime
    }
}

extension Abacus {
    static let mock: Abacus = Abacus()
}
