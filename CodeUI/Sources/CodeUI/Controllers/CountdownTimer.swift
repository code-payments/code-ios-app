//
//  CountdownTimer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public class CountdownTimer: ObservableObject {
    
    @Published public private(set) var state: State = .idle
    
    @Published public private(set) var secondsRemaining: Int
    
    private let secondsInitial: Int
    private var startDate: Date?
    private var displayLink: CADisplayLink?
    
    public var formattedTimeString: String {
        let seconds = secondsRemaining % 60
        let minutes = (secondsRemaining / 60) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Init -
    
    public init(seconds: Int) {
        self.secondsInitial = seconds
        self.secondsRemaining = seconds
        self.displayLink = CADisplayLink(target: self, selector: #selector(tick(displayLink:)))
        
        stop()
        
        displayLink?.add(to: .current, forMode: .default)
    }
    
    public func start() {
        guard state == .idle else {
            return
        }
        
        startDate = .now()
        state = .running
        displayLink?.isPaused = false
    }
    
    public func restart() {
        secondsRemaining = secondsInitial
        start()
    }
    
    public func stop() {
        displayLink?.isPaused = true
        state = .idle
    }
    
    private func finish() {
        displayLink?.isPaused = true
        state = .idle
    }
    
    // MARK: - Display Link -
    
    @objc private func tick(displayLink: CADisplayLink) {
        guard let startDate = startDate else {
            return
        }

        let elapsed = Date.now().timeIntervalSince1970 - startDate.timeIntervalSince1970
        let remaining = secondsInitial - Int(elapsed)
        
        if remaining <= 0 {
            finish()
        }
        
        let newValue = max(remaining, 0)
        if newValue != secondsRemaining {
            secondsRemaining = newValue
        }
    }
}

// MARK: - State -

extension CountdownTimer {
    public enum State {
        case idle
        case running
        case finished
    }
}
