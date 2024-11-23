//
//  Debouncer.swift
//  Code
//
//  Created by Dima Bart on 2024-11-22.
//

import Foundation
import FlipchatServices

@MainActor
class Debouncer {
    
    private var task: Task<Void, Error>?
    
    private let timeout: Int
    
    init(seconds: Int) {
        self.timeout = seconds
    }
    
    func execute(_ action: @escaping () throws -> Void) rethrows {
        task?.cancel()
        task = Task {
            guard !Task.isCancelled else {
                return
            }
            
            try await Task.delay(seconds: timeout)
            
            guard !Task.isCancelled else {
                return
            }
            
            try action()
        }
    }
}
