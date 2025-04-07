//
//  HandleView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct HandleView: View {
    
    public init() {}
    
    public var body: some View {
        RoundedRectangle(cornerRadius: 5.0)
            .fill(Color.textMain.opacity(0.1))
            .frame(width: 50, height: 5)
    }
}

// MARK: - Previews -

struct HandleView_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            HandleView()
        }
        .previewLayout(.fixed(width: 320, height: 500))
    }
}
