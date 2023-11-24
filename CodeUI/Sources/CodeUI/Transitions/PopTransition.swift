//
//  PopTransition.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

struct PopTransition: ViewModifier {
    
    var initial: CGFloat
    var progress: CGFloat
    
    init(initial: CGFloat, progress: CGFloat) {
        self.initial = initial
        self.progress = progress
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 - ((1.0 - progress) * initial))
            .opacity(Double(progress))
    }
}

extension AnyTransition {
    public static func pop(minimumScale: CGFloat) -> AnyTransition {
        .modifier(
            active: PopTransition(initial: minimumScale, progress: 0.0),
            identity: PopTransition(initial: minimumScale, progress: 1.0)
        )
    }
}
