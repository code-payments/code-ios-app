//
//  Poller.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public class Poller {
    
    private let timer: Timer
    
    public init(seconds: TimeInterval, fireImmediately: Bool = false, action: @escaping () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in
            action()
        }
        
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        
        if fireImmediately {
            action()
        }
    }
    
    deinit {
        timer.invalidate()
    }
}
