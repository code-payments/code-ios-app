//
//  Conditional.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

extension View {
    
    @ViewBuilder
    public func `if`<T>(_ condition: Bool, modify: (Self) -> T) -> some View where T: View {
        if condition {
            modify(self)
        } else {
            self
        }
    }
}
