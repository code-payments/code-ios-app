//
//  RedundancyContainer.swift
//  Code
//
//  Created by Dima Bart on 2021-01-28.
//

import Foundation

struct RedundancyContainer<T> where T: Hashable {
    
    private typealias Selection = (value: T, count: Int)
    
    private(set) var value: T?
    
    private var stack: [Selection] = []
    
    let threshold: Int
    
    // MARK: - Init -
    
    init(threshold: Int) {
        self.threshold = threshold
    }
    
    // MARK: - Insert -
    
    mutating func insert(_ value: T) {
        let index = stack.firstIndex {
            $0.value == value
        }
        
        if let index = index {
            var selection = stack[index]
            selection.count = selection.count + 1
            stack[index] = selection
        } else {
            let selection = (value, 1)
            stack.insert(selection, at: 0)
        }
        
        update()
    }
    
    mutating func reset() {
        value = nil
        stack.removeAll()
    }
    
    private mutating func update() {
        for selection in stack {
            if selection.count >= threshold {
                if selection.value != value {
                    reset()
                    value = selection.value
                    stack.append(selection)
                }
                break
            }
        }
    }
}
