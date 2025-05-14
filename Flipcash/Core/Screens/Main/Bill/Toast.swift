//
//  Toast.swift
//  Code
//
//  Created by Dima Bart on 2025-04-22.
//

import Foundation
import FlipcashCore

struct ToastQueue {
    
    private var queue: [Toast] = []
    
    var hasToasts: Bool {
        !queue.isEmpty
    }
    
    init() {
        
    }
    
    mutating func insert(_ toast: Toast) {
        if let nextToast = queue.first, toast.negates(toast: nextToast) {
            queue.remove(at: 0)
//            trace(.note, components: "Inserted negating toast, removing both: \(toast.isDeposit ? "+" : "-")\(toast.amount.formatted(suffix: nil))", "Queue count: \(queue.count)")
        } else {
            queue.insert(toast, at: 0)
//            trace(.note, components: "Inserting toast: \(toast.isDeposit ? "+" : "-")\(toast.amount.formatted(suffix: nil))", "Queue count: \(queue.count)")
        }
    }
    
    mutating func pop() -> Toast? {
        queue.popLast()
    }
}

struct Toast: Equatable, Hashable {
    let amount: Fiat
    let isDeposit: Bool
    
    func negates(toast: Toast) -> Bool {
        self.amount == toast.amount &&
        self.isDeposit != toast.isDeposit
    }
}
