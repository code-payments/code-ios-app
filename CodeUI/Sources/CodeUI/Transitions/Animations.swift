//
//  Animations.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

extension Animation {
    public static var easeOutSlower: Animation {
        Animation
            .easeOut
            .speed(0.5)
    }
    
    public static var easeOutFastest: Animation {
        Animation
            .easeOut
            .speed(2.0)
    }
    
    public static var springFaster: Animation {
        Animation
            .spring(dampingFraction: 0.5)
            .speed(1.5)
    }
    
    public static var springFastest: Animation {
        Animation
            .spring(dampingFraction: 0.5)
            .speed(2.0)
    }
    
    public static var springFastestDamped: Animation {
        Animation
            .spring(dampingFraction: 0.6)
            .speed(2.0)
    }
}

extension AnyTransition {
    public static var crossFade: AnyTransition {
        AnyTransition
            .opacity
            .animation(.easeOutSlower)
    }
}

@MainActor
public func withoutAnimation(block: VoidAction) {
    var transaction = Transaction(animation: .linear.speed(.greatestFiniteMagnitude))
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        block()
    }
}
