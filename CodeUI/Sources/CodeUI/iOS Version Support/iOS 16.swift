//
//  iOS 16.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

private struct CompatibilityModifier: ViewModifier {
    
    var kind: Kind
    
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            switch kind {
            case .scrollContentBackground(let visibility):
                content
                    .scrollContentBackground(visibility)
            }
        } else {
            content
        }
    }
}

extension CompatibilityModifier {
    enum Kind {
        case scrollContentBackground(Visibility)
    }
}

extension View {
    public func backportScrollContentBackground(_ visibility: Visibility) -> some View {
        return modifier(CompatibilityModifier(kind: .scrollContentBackground(visibility)))
    }
}
