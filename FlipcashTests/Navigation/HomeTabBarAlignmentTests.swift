//
//  HomeTabBarAlignmentTests.swift
//  FlipcashTests
//
//  The Group Money shell's tab bar at the leading edge instead of the centre,
//  behind `.leftAlignedTabBar`: the flag, who sees its toggle, where the bar
//  goes in each state, the shell's own bar on both of its tabs (the small bar
//  at the leading edge, which both OS paths draw, and the centred legacy
//  pill), and the iOS 26 system bar, which the flag hides in favour of the
//  small bar.
//

import SwiftUI
import Testing
import UIKit
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Left-aligned tab bar", .serialized)
struct HomeTabBarAlignmentTests {

    // MARK: - Flag

    @Test("the flag exists under its stored name")
    func flag_exists() {
        #expect(BetaFlags.Option(rawValue: "leftAlignedTabBar") == .leftAlignedTabBar)
    }

    @Test("the flag is off until someone turns it on")
    func flag_defaultsOff() {
        #expect(BetaFlags.Option.leftAlignedTabBar.isOnByDefault == false)
    }

    @Test("the flag is a developer flag, not a public beta")
    func flag_isDeveloper() {
        #expect(BetaFlags.Option.leftAlignedTabBar.availability == .developer)
    }

    @Test("the toggle is titled like its neighbours, says the bar turns small, and says it needs Group Money UI")
    func flag_copy() {
        #expect(BetaFlags.Option.leftAlignedTabBar.localizedTitle == "Left-Aligned Tab Bar")
        #expect(BetaFlags.Option.leftAlignedTabBar.localizedDescription == "If enabled, the Groups and Money tab bar is a small bar at the left edge instead of the center. Needs Group Money UI on.")
    }

    // MARK: - Who sees the toggle

    @Test("the toggle is hidden from a user who is neither staff nor unlocked")
    func toggle_hiddenFromEveryoneElse() {
        #expect(!BetaFlags.developerOptions(isStaff: false, accessGranted: false).contains(.leftAlignedTabBar))
    }

    @Test("the toggle is shown to staff on a device that is not unlocked, right after Group Money UI")
    func toggle_shownToStaff() throws {
        let options = BetaFlags.developerOptions(isStaff: true, accessGranted: false)
        let groupMoney = try #require(options.firstIndex(of: .groupMoneyUI))
        #expect(options.firstIndex(of: .leftAlignedTabBar) == groupMoney + 1, "\(options)")
    }

    @Test("the toggle is shown on a developer-unlocked device, right after Group Money UI")
    func toggle_shownWhenUnlocked() throws {
        let options = BetaFlags.developerOptions(isStaff: false, accessGranted: true)
        let groupMoney = try #require(options.firstIndex(of: .groupMoneyUI))
        #expect(options.firstIndex(of: .leftAlignedTabBar) == groupMoney + 1, "\(options)")
    }

    // MARK: - Where the bar goes

    @Test("shell off: the flag does nothing", arguments: [false, true])
    func placement_shellOff(leftAligned: Bool) {
        #expect(HomeTabLayout.standard.barAlignment(leftAligned: leftAligned) == .center)
    }

    @Test("shell on, flag off: the bar stays centred")
    func placement_shellOnFlagOff() {
        #expect(HomeTabLayout.groupMoney.barAlignment(leftAligned: false) == .center)
    }

    @Test("shell on, flag on: the bar goes to the leading edge")
    func placement_shellOnFlagOn() {
        #expect(HomeTabLayout.groupMoney.barAlignment(leftAligned: true) == .leading)
    }

    @Test("the leading edge takes the small bar, the centre the legacy pill")
    func size_followsAlignment() {
        #expect(HomeTabBar.Size(for: .leading) == .compact)
        #expect(HomeTabBar.Size(for: .center) == .regular)
    }

    // MARK: - Small bar

    // Both OS paths draw the small bar the same way: `HomeTabBar` at `.compact` in a
    // `LeadingTabBarSlot`. Its numbers are the iOS 26 system bar's, measured on a 402pt-wide
    // iPhone: glass from x=107 to x=295 and y=791 to y=853 in an 874pt window.

    @Test("small bar: the system bar's size, 188pt by 62pt with two tabs")
    func smallBar_size() {
        #expect(HomeTabBar.compactWidth(tabCount: 2) == 188)
        #expect(HomeTabBar.height(.compact) == 62)
    }

    @Test("small bar: its top is where the system bar's inset ends, 83pt up from the screen bottom")
    func smallBar_top() {
        #expect(HomeTabView.leadingBarTop == 83)
    }

    @Test("small bar: Groups and Money draw it on the same frame, 21pt in from the leading edge and 21pt up from the bottom")
    func smallBar_sameFrameOnBothTabs() async throws {
        let bar = BarState(selection: .chat, alignment: .leading)
        let host = HostedShellBar(state: bar)
        defer { host.close() }

        let groups = try await host.settledFrame()
        bar.selection = .wallet
        let money = try await host.settledFrame()

        #expect(Self.same(groups, money), "Groups \(groups), Money \(money)")
        #expect(Self.same(groups, CGRect(x: 21, y: 874 - 21 - 62, width: 188, height: 62)), "bar \(groups)")
    }

    // MARK: - Legacy pill, centred

    @Test("legacy pill: Groups and Money draw it on the same frame, 318pt wide and 42pt in from each side")
    func legacyPill_sameFrameOnBothTabs() async throws {
        let pill = BarState(selection: .chat, alignment: .center)
        let host = HostedShellBar(state: pill)
        defer { host.close() }

        let groups = try await host.settledFrame()
        pill.selection = .wallet
        let money = try await host.settledFrame()

        #expect(Self.same(groups, money), "Groups \(groups), Money \(money)")
        #expect(abs(groups.width - 318) <= 0.5, "pill \(groups)")
        #expect(abs(groups.minX - 42) <= 0.5, "pill \(groups)")
        #expect(abs(groups.height - 58) <= 0.5, "pill \(groups)")
    }

    // MARK: - System bar, hosted

    @Test("system bar, flag off: Groups and Money draw it on the same frame, centred")
    func systemBar_flagOffCentredOnBothTabs() async throws {
        guard #available(iOS 26, *) else { return }
        let host = try await HostedBar(flags: BarFlags(showsGroupMoney: true, leftAligned: false))
        defer { host.close() }

        let groups = try await host.settledItems(selected: "Groups")
        host.sessionContainer.appRouter.showTab(.wallet)
        let money = try await host.settledItems(selected: "Money")

        #expect(Self.same(groups, money), "Groups \(groups), Money \(money)")
        #expect(abs(groups.midX - host.window.bounds.midX) <= 1, "items \(groups)")
    }

    @Test("system bar, flag on: hidden on Groups and on Money, for the small bar")
    func systemBar_flagOnHidden() async throws {
        guard #available(iOS 26, *) else { return }
        let host = try await HostedBar(flags: BarFlags(showsGroupMoney: true, leftAligned: true))
        defer { host.close() }

        try await host.waitForSystemBar(hidden: true)
        host.sessionContainer.appRouter.showTab(.wallet)
        try await host.waitForSelectedTitle("Money")
        try await host.waitForSystemBar(hidden: true)
    }

    @Test("system bar: today's layout keeps it with the flag on")
    func systemBar_standardLayoutIgnoresFlag() async throws {
        guard #available(iOS 26, *) else { return }
        let host = try await HostedBar(flags: BarFlags(showsGroupMoney: false, leftAligned: true))
        defer { host.close() }

        try await host.waitForSystemBar(hidden: false)
        #expect((host.tabBarController?.tabBar.items?.count ?? 0) >= 4)
    }

    @Test("system bar: a flip on and back off keeps the selected tab, and the tab content's bottom inset")
    func systemBar_flagFlipKeepsSelectionAndInset() async throws {
        guard #available(iOS 26, *) else { return }
        let flags = BarFlags(showsGroupMoney: true, leftAligned: false)
        let host = try await HostedBar(flags: flags)
        defer { host.close() }
        host.sessionContainer.appRouter.showTab(.wallet)
        _ = try await host.settledItems(selected: "Money")
        let systemInset = try await host.settledContentBottomInset()

        flags.leftAligned = true
        try await host.waitForSystemBar(hidden: true)
        #expect(host.selectedTitle == "Money")
        let smallBarInset = try await host.settledContentBottomInset()
        #expect(abs(smallBarInset - systemInset) <= 0.5, "small bar \(smallBarInset), system bar \(systemInset)")

        flags.leftAligned = false
        _ = try await host.settledItems(selected: "Money")
        let restored = try await host.settledContentBottomInset()
        #expect(abs(restored - systemInset) <= 0.5, "restored \(restored), system bar \(systemInset)")
    }

    // MARK: - Flag stand-in

    @Test("the suite's flag stand-in answers off for every flag it is not given, whatever the test host has stored")
    func standIn_ignoresStoredFlags() throws {
        try BetaFlags.withEveryOptionStored {
            let flags = AlignmentFlags(state: BarFlags(showsGroupMoney: false, leftAligned: false))
            for option in BetaFlags.Option.allCases {
                #expect(!flags.hasEnabled(option), "\(option)")
            }
        }
    }

    // MARK: - Helpers

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 0.5 && abs(a.minY - b.minY) <= 0.5
            && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
    }
}

// MARK: - Hosted bar -

/// The shell bar's selection and alignment, changed by a test while the bar stays hosted.
@Observable
private final class BarState {
    var selection: HomeTab
    var alignment: HorizontalAlignment
    var frame: CGRect = .zero

    init(selection: HomeTab, alignment: HorizontalAlignment) {
        self.selection = selection
        self.alignment = alignment
    }
}

/// The Group Money shell's own bar in a 402pt-wide window, placed as `HomeTabView` places it:
/// the small bar in its leading slot, or the legacy pill centred at the bottom. `HomeTabView`
/// draws the legacy pill only before iOS 26, so the bar is hosted on its own.
@MainActor
private struct HostedShellBar {
    let window: UIWindow
    let state: BarState

    init(state: BarState) {
        let view = BarScreen(state: state)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
        self.state = state
    }

    func close() {
        window.isHidden = true
    }

    /// The bar's frame in the window once two reads 100ms apart agree.
    func settledFrame() async throws -> CGRect {
        var last: CGRect = .zero
        var settled: CGRect = .zero
        try await waitUntil(timeout: .seconds(30), pollInterval: .milliseconds(100)) {
            window.layoutIfNeeded()
            let frame = state.frame
            defer { last = frame }
            guard frame.width > 0, frame == last else { return false }
            settled = frame
            return true
        }
        return settled
    }

    private struct BarScreen: View {
        let state: BarState

        var body: some View {
            if state.alignment == .leading {
                LeadingTabBarSlot {
                    bar
                }
            } else {
                VStack {
                    Spacer()
                    bar.padding(.horizontal, HomeTabView.legacyPillInset)
                }
            }
        }

        private var bar: some View {
            HomeTabBar(
                selection: Binding { state.selection } set: { state.selection = $0 },
                layout: .groupMoney,
                size: HomeTabBar.Size(for: state.alignment)
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.frame = $0 }
        }
    }
}

/// The two gates the bar reads, flipped by a test while one view stays hosted. Reading them
/// inside a view's body tracks them, so a flip redraws the view as a stored flag change would.
@MainActor
@Observable
private final class BarFlags {
    var showsGroupMoney: Bool
    var leftAligned: Bool

    init(showsGroupMoney: Bool, leftAligned: Bool) {
        self.showsGroupMoney = showsGroupMoney
        self.leftAligned = leftAligned
    }
}

/// Answers the shell's gate and the alignment flag from ``BarFlags``, and every other flag off, so
/// a flag stored on the test host (other suites write them to `UserDefaults.standard`) does not
/// reach this suite through this stand-in. The inherited members it does not override, such as
/// `accessGranted`, and code that reads `BetaFlags.shared` still answer from the store.
@MainActor
private final class AlignmentFlags: BetaFlags {
    let state: BarFlags

    init(state: BarFlags) {
        self.state = state
        super.init()
    }

    override func showsGroupMoneyUI(isStaff: Bool) -> Bool {
        state.showsGroupMoney
    }

    override func hasEnabled(_ option: Option) -> Bool {
        option == .leftAlignedTabBar && state.leftAligned
    }
}

/// `HomeTabView` in a 402pt-wide window, and the system tab bar it draws.
@MainActor
private struct HostedBar {
    let window: UIWindow
    let sessionContainer: SessionContainer

    @available(iOS 26, *)
    init(flags: BarFlags) async throws {
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let view = HomeTabView()
            .environment(AlignmentFlags(state: flags) as BetaFlags)
            .injectingEnvironment(from: sessionContainer)
            .injectingEnvironment(from: Container.mock)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
        self.sessionContainer = sessionContainer

        // The bar controller exists, with its items, whether or not the bar shows.
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                return (Self.tabBarController(in: window)?.tabBar.items?.count ?? 0) >= 2
            }
        } catch {
            Issue.record("no tab bar controller with items")
            window.isHidden = true
            throw error
        }
    }

    func close() {
        window.isHidden = true
    }

    var tabBarController: UITabBarController? {
        Self.tabBarController(in: window)
    }

    /// The selected item's title, read off the bar's controller, so it answers while the bar is hidden.
    var selectedTitle: String? {
        tabBarController?.tabBar.selectedItem?.title
    }

    func waitForSelectedTitle(_ title: String) async throws {
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                return selectedTitle == title
            }
        } catch {
            Issue.record("selected \(selectedTitle ?? "-"), wanted \(title)")
            throw error
        }
    }

    /// Waits until the system bar is hidden or showing. Showing means the controller has the bar
    /// up and the bar has laid out its items.
    func waitForSystemBar(hidden: Bool) async throws {
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                guard let controller = tabBarController else { return false }
                if hidden { return controller.isTabBarHidden }
                guard !controller.isTabBarHidden, let bar = visibleBar(),
                      let itemCount = bar.items?.count, itemCount >= 2
                else { return false }
                return TabBarItemLocator.itemFrames(in: bar).count == itemCount
            }
        } catch {
            Issue.record("system bar hidden \(tabBarController?.isTabBarHidden.description ?? "-"), wanted \(hidden)")
            throw error
        }
    }

    /// The selected tab's bottom inset as its scrolling content sees it: the tallest scroll view's
    /// adjusted content inset, once two reads 100ms apart agree. Read off the scroll view rather
    /// than a view controller's safe area, since SwiftUI hands the small bar's inset to the scroll
    /// view without it showing on the hosting controllers.
    func settledContentBottomInset() async throws -> CGFloat {
        var last: CGFloat = -1
        var settled: CGFloat = 0
        try await waitUntil(timeout: .seconds(30), pollInterval: .milliseconds(100)) {
            window.layoutIfNeeded()
            guard let selected = tabBarController?.selectedViewController,
                  let scroll = Self.tallestScrollView(in: selected.view)
            else { return false }
            let inset = scroll.adjustedContentInset.bottom
            defer { last = inset }
            guard inset == last else { return false }
            settled = inset
            return true
        }
        return settled
    }

    func visibleBar() -> UITabBar? {
        Self.tabBar(in: window)
    }

    /// The bar's item buttons in window coordinates, left to right. Window coordinates, because a
    /// bar moved as a whole keeps its items where they were in its own.
    func windowItemFrames() -> [CGRect] {
        guard let bar = visibleBar() else { return [] }
        return TabBarItemLocator.itemFrames(in: bar).map { bar.convert($0, to: nil) }
    }

    /// The item frames once two reads 100ms apart agree.
    func settledFrames() async throws -> [CGRect] {
        var last: [CGRect] = []
        var settled: [CGRect] = []
        try await waitUntil(timeout: .seconds(30), pollInterval: .milliseconds(100)) {
            window.layoutIfNeeded()
            let frames = windowItemFrames()
            defer { last = frames }
            guard !frames.isEmpty, frames == last else { return false }
            settled = frames
            return true
        }
        return settled
    }

    /// The union of the bar's items once the bar shows, `selected` is the selected item, and the
    /// frames have settled.
    func settledItems(selected: String) async throws -> CGRect {
        try await waitForSystemBar(hidden: false)
        try await waitForSelectedTitle(selected)
        let frames = try await settledFrames()
        return frames.dropFirst().reduce(frames[0]) { $0.union($1) }
    }

    private static func tabBarController(in window: UIWindow) -> UITabBarController? {
        var queue = window.rootViewController.map { [$0] } ?? []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let controller = next as? UITabBarController { return controller }
            queue.append(contentsOf: next.children)
        }
        return nil
    }

    private static func tallestScrollView(in view: UIView) -> UIScrollView? {
        var tallest = view as? UIScrollView
        for subview in view.subviews {
            if let found = tallestScrollView(in: subview), found.bounds.height > (tallest?.bounds.height ?? 0) {
                tallest = found
            }
        }
        return tallest
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden { return bar }
        for subview in view.subviews {
            if let bar = tabBar(in: subview) { return bar }
        }
        return nil
    }
}
