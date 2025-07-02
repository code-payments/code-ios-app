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
    private let didSet: (() -> Void)?
    
    init(_ valueBlock: @escaping () -> T, didSet: (() -> Void)? = nil) {
        self.valueBlock = valueBlock
        self.didSet = didSet
        
        let start = Date.now
        self.value = valueBlock()
        if let time = Date.now.formattedMilliseconds(from: start, threshold: 5) {
            print("[Updateable] Loading <\(T.self)>, took: \(time)")
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDatabaseDidChange), name: .databaseDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .databaseDidChange, object: nil)
    }
    
    @objc private func handleDatabaseDidChange() {
        let start = Date.now
        value = valueBlock()
        if let time = Date.now.formattedMilliseconds(from: start, threshold: 5) {
            print("[Updateable] Loading <\(T.self)>, took: \(time)")
        }
    }
}

extension Date {
    func formattedMilliseconds(from reference: Date) -> String {
        let delta = timeIntervalSince(reference)
        let ms = delta * 1000
        return String(format: "%.3f ms", ms)
    }
    
    func formattedMilliseconds(from reference: Date, threshold: Double) -> String? {
        let delta = timeIntervalSince(reference)
        let ms = delta * 1000
        let text = String(format: "%.3f ms", ms)
        
        if ms >= threshold {
            return text
        } else {
            return nil
        }
    }
}
