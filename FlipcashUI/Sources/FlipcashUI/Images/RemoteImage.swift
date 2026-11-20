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
            .placeholder { Circle().fill(Color.remoteImagePlaceholder) }
            .resizable()
    }
}

private extension Color {
    /// The disc shown while the image loads: black 50% in dark, Apple's `tertiarySystemFill` grey in light.
    static let remoteImagePlaceholder = Color(light: Color(r: 118, g: 118, b: 128, o: 0.12), dark: .black.opacity(0.5))
}
