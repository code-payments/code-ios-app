//
//  Image+CompileTime.swift
//  Code
//
//  Created by Dima Bart on 2024-10-02.
//

import SwiftUI

extension Image {
    enum CompileTimeImage: String {
        case brandLarge
    }
    
    init(with compileTimeImage: CompileTimeImage) {
        self.init(compileTimeImage.rawValue, bundle: nil)
    }
}
