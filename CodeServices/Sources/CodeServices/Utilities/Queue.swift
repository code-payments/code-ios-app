//
//  Queue.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

@MainActor
public class Queue {
    
    public typealias QueueAction = () -> Void
    
    private var actions: [QueueAction] = []
    private var isBlocked: Bool
    
    public init(isBlocked: Bool) {
        self.isBlocked = isBlocked
    }
    
    public func setBlocked() {
        self.isBlocked = true
    }
    
    public func setUnblocked() {
        self.isBlocked = false
        fulfill()
    }
    
    public func enqueue(_ action: @escaping QueueAction) {
        if isBlocked {
            actions.append(action)
        } else {
            action()
        }
    }
    
    private func fulfill() {
        while !actions.isEmpty {
            actions.removeFirst()()
        }
    }
}
