//
//  ListFooter.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ListFooter: View {
    
    public let title: String
    
    public init(_ title: String) {
        self.title = title
    }
    
    public var body: some View {
        Text(title)
            .foregroundColor(.textSecondary)
            .padding(.top, 5)
            .padding([.leading, .trailing], 20)
    }
}
