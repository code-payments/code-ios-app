//
//  RemoteImage.swift
//  Code
//
//  Created by Dima Bart on 2025-10-24.
//

import Kingfisher
import SwiftUI

struct RemoteImage: View {
    
    let url: URL
    
    init(url: URL?) {
        self.url = url ?? URL(string: "https://example.com")!
    }
    
    var body: some View {
        KFImage(url)
            .placeholder { Circle().fill(Color.black.opacity(0.5)) }
            .resizable()
    }
}
