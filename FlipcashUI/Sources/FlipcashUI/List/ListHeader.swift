//
//  ListHeader.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct ListHeader: View {
    
    public let title: String
    
    public init(_ title: String) {
        self.title = title
    }
    
    public var body: some View {
        Text(title)
            .textCase(.none)
            .font(.appTextSmall)
            .foregroundStyle(.textSecondary)
            .padding(.bottom, 5)
    }
}
