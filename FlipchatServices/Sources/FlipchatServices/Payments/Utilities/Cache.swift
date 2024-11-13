//
//  Cache.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

class Cache {
    
    private var store: [String: Item] = [:]
    
    // MARK: - Init -
    
    init() {}
    
    func insert<T>(_ value: T, forKey key: String, expireIn ttl: TimeInterval) {
        store[key] = Item(
            value: value,
            expiry: ttl,
            timestamp: .now
        )
    }
    
    func item<T>(forKey key: String) -> T? {
        guard let item = store[key] else {
            return nil
        }
        
        guard item.isValid else {
            return nil
        }
        
        guard let value = item.value as? T else {
            return nil
        }
        
        return value
    }
    
    func remove(forKey key: String) {
        store.removeValue(forKey: key)
    }
}

// MARK: - Item -

extension Cache {
    struct Item {
        
        var value: Any
        var expiry: TimeInterval
        var timestamp: TimeInterval
        
        var isValid: Bool {
            (timestamp + expiry) > .now
        }
    }
}

// MARK: - TimeInterval -

extension TimeInterval {
    static var now: TimeInterval {
        Date().timeIntervalSince1970
    }
    
    static func minutes(_ minutes: Int) -> TimeInterval {
        .now + TimeInterval(minutes) * 60
    }
}
