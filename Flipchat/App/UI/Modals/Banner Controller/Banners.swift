//
//  Banners.swift
//  Flipchat
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import UIKit
import SwiftUI
import FlipchatServices

struct BannerContainer: View {
    
    @EnvironmentObject private var banners: Banners
    
    var body: some View {
        ZStack {}
        .banner(banners.banner)
    }
}

@MainActor
public class Banners: ObservableObject {
    
    @Published public private(set) var banner: Banner? = nil
    
    private var queue: [Banner] = []
    
    private var isPresenting: Bool = false
    
    private let window: UIWindow
    
    // MARK: - Init -
    
    public init() {
        self.window = UIWindow(frame: UIScreen.main.bounds)
        
        let container = BannerContainer()
            .environmentObject(self)
        
        let controller = UIHostingController(rootView: container)
        controller.view.backgroundColor = .clear
        
        window.rootViewController = controller
        window.backgroundColor = .clear
        window.windowLevel = UIWindow.Level(UIWindow.Level.normal.rawValue + 1)
        window.isHidden = false
        window.isUserInteractionEnabled = false
        
        toggle(presenting: false)
    }
    
    // MARK: - Actions -
    
    @discardableResult
    public func show(style: Banner.Style, title: String?, description: String?, position: Banner.Position = .top, isDismissable: Bool? = nil, actionStyle: Banner.ActionStyle = .inline, actions: [Banner.Action] = []) -> UUID {
        let banner = Banner(
            style: style,
            title: title,
            description: description,
            position: position,
            isDismissable: isDismissable,
            actionStyle: actionStyle,
            actions: actions
        )
        
        show(banner)
        
        return banner.id
    }
    
    public func dismiss(id: UUID) {
        if banner?.id == id {
            dismissCurrent()
        }
    }
    
    private func dismissCurrent() {
        Task {
            try await dismissAndConsume()
        }
    }
    
    private func show(_ banner: Banner) {
        enque(banner)
    }
    
    private func show(_ banners: [Banner]) {
        banners.forEach { show($0) }
    }
            
    // MARK: - Queue -
    
    private func enque(_ newBanner: Banner) {
        if isPresenting {
            queue.append(newBanner)
        } else {
            consume(newBanner)
        }
    }
    
    private func consume(_ newBanner: Banner) {
        toggle(presenting: true)
        
        var consumableBanner = newBanner
        consumableBanner.setDismissAction { [weak self] in
            self?.dismissCurrent()
        }
        
        banner = consumableBanner
        window.isUserInteractionEnabled = true
    }
    
    private func dismissAndConsume() async throws {
        window.isUserInteractionEnabled = false
        banner = nil
        
        // Should be longer than the animation
        // to dismiss the banner
        try await Task.delay(milliseconds: 500)
        
        if let nextBanner = dequeNext() {
            consume(nextBanner)
        } else {
            toggle(presenting: false)
        }
    }
    
    private func dequeNext() -> Banner? {
        guard !queue.isEmpty else {
            return nil
        }
        
        return queue.remove(at: 0)
    }
    
    private func toggle(presenting: Bool) {
        isPresenting = presenting
    }
}

// MARK: - Mock -

extension Banners {
    public static let mock = Banners()
}
