//
//  RemoteImage.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-10-24.
//

import Kingfisher
import SwiftUI

public struct RemoteImage: View {

    let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        KFImage(url)
            .placeholder { Circle().fill(Color.black.opacity(0.5)) }
            .resizable()
    }
}
