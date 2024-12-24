//
//  AutoUpdating.swift
//  Code
//
//  Created by Dima Bart on 2024-12-23.
//

import SwiftUI

class Updateable<T>: ObservableObject {
    
    @Published private(set) var value: T
    
    private let valueBlock: () -> T
    
    init(_ valueBlock: @escaping () -> T) {
        self.valueBlock = valueBlock
        
        let start = Date.now
        self.value = valueBlock()
        print("[Updateable] Loading <\(T.self)>, took: \(Date.now.formattedMilliseconds(from: start))")
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDatabaseDidChange), name: .databaseDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .databaseDidChange, object: nil)
    }
    
    @objc private func handleDatabaseDidChange() {
        let start = Date.now
        value = valueBlock()
        print("[Updateable] Updating <\(T.self)>, took: \(Date.now.formattedMilliseconds(from: start))")
    }
}

extension Date {
    func formattedMilliseconds(from reference: Date) -> String {
        let delta = timeIntervalSince(reference)
        let ms = delta * 1000
        return String(format: "%.3f ms", ms)
    }
}
