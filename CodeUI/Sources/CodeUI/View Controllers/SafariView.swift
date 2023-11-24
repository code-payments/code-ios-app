//
//  SafariView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI
import SafariServices

public struct SafariView: UIViewControllerRepresentable {
    
    public let url: URL
    public let barCollapsingEnabled: Bool
    public let entersReaderIfAvailable: Bool
    
    public init(url: URL, barCollapsingEnabled: Bool = false, entersReaderIfAvailable: Bool = false) {
        self.url = url
        self.barCollapsingEnabled = barCollapsingEnabled
        self.entersReaderIfAvailable = entersReaderIfAvailable
    }
    
    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = barCollapsingEnabled
        configuration.entersReaderIfAvailable = entersReaderIfAvailable
        
        return SFSafariViewController(url: url, configuration: configuration)
    }
    
    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#endif
