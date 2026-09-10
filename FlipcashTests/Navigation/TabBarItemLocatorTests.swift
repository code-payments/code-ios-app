//
//  TabBarItemLocatorTests.swift
//  FlipcashTests
//

import UIKit
import Testing
@testable import Flipcash

/// Drives a real, windowed `UITabBarController` so the item lookup is checked
/// against the bar UIKit actually builds on this OS, not a stand-in.
@MainActor
@Suite("Tab bar item locator")
struct TabBarItemLocatorTests {

    private func makeWindowedTabBar() async -> UITabBar {
        let controller = UITabBarController()
        controller.viewControllers = HomeTab.allCases.map { tab in
            let child = UIViewController()
            child.tabBarItem = UITabBarItem(title: tab.accessibilityLabel, image: nil, tag: tab.rawValue)
            return child
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            controller.tabBar.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
        return controller.tabBar
    }

    @Test("one item frame per tab, in display order")
    func itemFrames_oneLaidOutFramePerTab() async {
        let bar = await makeWindowedTabBar()
        let frames = TabBarItemLocator.itemFrames(in: bar)
        #expect(frames.count == HomeTab.allCases.count)
        let lefts = frames.map(\.minX)
        #expect(lefts == lefts.sorted())
        #expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test("a point inside the last item resolves to the You tab")
    func tab_atLastItemCenter_isYou() async {
        let bar = await makeWindowedTabBar()
        let frames = TabBarItemLocator.itemFrames(in: bar)
        guard let last = frames.last, let first = frames.first else {
            Issue.record("no item frames found")
            return
        }
        let lastCenter = CGPoint(x: last.midX, y: last.midY)
        let firstCenter = CGPoint(x: first.midX, y: first.midY)
        #expect(TabBarItemLocator.tab(at: lastCenter, in: bar, tabs: HomeTab.allCases) == .tipCard)
        #expect(TabBarItemLocator.tab(at: firstCenter, in: bar, tabs: HomeTab.allCases) == .scan)
    }

    @Test("a point outside every item resolves to nothing")
    func tab_outsideItems_isNil() async {
        let bar = await makeWindowedTabBar()
        let offBar = CGPoint(x: -50, y: -50)
        #expect(TabBarItemLocator.tab(at: offBar, in: bar, tabs: HomeTab.allCases) == nil)
    }
}
