//
//  LazyView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct LazyView<Content: View>: View {
    
    public let content: () -> Content
    
    public init(_ content: @autoclosure @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
        content()
    }
}
