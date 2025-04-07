//
//  Preview.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Preview<Content>: View where Content: View {
    
    public let devices: [PreviewDevice]
    public let content: () -> Content
    
    // MARK: - Init -
    
    public init(devices: PreviewDevice..., @ViewBuilder content: @escaping () -> Content) {
        self.devices = devices
        self.content = content
    }
    
    // MARK: - Body -
    
    public var body: some View {
        Group {
            ForEach(devices) { device in
                content()
                    .previewDevice(device)
            }
        }
    }
}

extension PreviewDevice: Identifiable {
    
    public static let iPhoneSE   = PreviewDevice(rawValue: "iPhone SE (2nd generation)")
    public static let iPhone     = PreviewDevice(rawValue: "iPhone 13")
    public static let iPhonePro  = PreviewDevice(rawValue: "iPhone 13 Pro")
    public static let iPhoneMax  = PreviewDevice(rawValue: "iPhone 13 Pro Max")
    public static let iPhoneMini = PreviewDevice(rawValue: "iPhone 13 mini")
    
    public var id: String {
        rawValue
    }
}
