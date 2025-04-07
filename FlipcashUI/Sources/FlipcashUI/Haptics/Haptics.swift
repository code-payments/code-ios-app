//
//  Haptics.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import UIKit

@MainActor
public enum Haptics {
    
    private static let impact = UIImpactFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
    
    public static func tap() {
        impact.impactOccurred(intensity: 1.0)
    }
    
    public static func buttonTap() {
        impact.impactOccurred(intensity: 0.9)
    }
    
    public static func softest() {
        impact.impactOccurred(intensity: 0.1)
    }
    
    public static func soft() {
        impact.impactOccurred(intensity: 0.35)
    }
    
    public static func medium() {
        impact.impactOccurred(intensity: 0.6)
    }
    
    public static func hard() {
        impact.impactOccurred(intensity: 0.8)
    }
    
    public static func hardest() {
        impact.impactOccurred(intensity: 0.9)
    }
    
    public static func vibrate() {
        notification.notificationOccurred(.error)
    }
}

#endif
