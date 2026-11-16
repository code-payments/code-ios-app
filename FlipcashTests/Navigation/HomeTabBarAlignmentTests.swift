//
//  HomeTabBarAlignmentTests.swift
//  FlipcashTests
//
//  The Group Money shell's tab bar at the leading edge instead of the centre,
//  behind `.leftAlignedTabBar`: the flag, who sees its toggle, where the bar
//  goes in each state, the legacy pill on both of its tabs in each alignment,
//  and the iOS 26 system bar, which the flag leaves centred, on both of its.
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

    @Test("the toggle is titled like its neighbours and says it needs Group Money UI")
    func flag_copy() {
        #expect(BetaFlags.Option.leftAlignedTabBar.localizedTitle == "Left-Aligned Tab Bar")
        #expect(BetaFlags.Option.leftAlignedTabBar.localizedDescription == "If enabled, the Groups and Money tab bar sits at the left edge instead of the center. Needs Group Money UI on.")
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

    // MARK: - System bar, hosted

    // The iOS 26 system bar has no public API that places it, so the flag leaves it centred. These
    // pin that down on both tabs, so a later attempt to move it has to change them on purpose.

    @Test("system bar: Groups and Money draw the bar on the same frame, centred, with the flag on or off", arguments: [false, true])
    func systemBar_sameFrameOnBothTabs(leftAligned: Bool) async throws {
        guard #available(iOS 26, *) else { return }
        let host = try await HostedBar(flags: BarFlags(showsGroupMoney: true, leftAligned: leftAligned))
        defer { host.close() }

        let groups = try await host.settledItems(selected: "Groups")
        host.sessionContainer.appRouter.showTab(.wallet)
        let money = try await host.settledItems(selected: "Money")

        #expect(Self.same(groups, money), "Groups \(groups), Money \(money)")
        #expect(abs(groups.midX - host.window.bounds.midX) <= 1, "items \(groups)")
    }

    @Test("system bar: flipping the flag with the shell showing leaves the bar where it was")
    func systemBar_flagFlipLeavesBar() async throws {
        guard #available(iOS 26, *) else { return }
        let flags = BarFlags(showsGroupMoney: true, leftAligned: false)
        let host = try await HostedBar(flags: flags)
        defer { host.close() }
        let centred = try await host.settledItems(selected: "Groups")

        flags.leftAligned = true
        let flipped = try await host.settledItems(selected: "Groups")

        #expect(Self.same(flipped, centred), "flipped \(flipped), centred \(centred)")
    }

    // MARK: - Legacy pill

    @Test("legacy pill: centred keeps its 42pt inset each side")
    func legacyPill_centred() {
        #expect(HomeTabView.legacyPillInsets(for: .center) == EdgeInsets(top: 0, leading: 42, bottom: 0, trailing: 42))
    }

    @Test("legacy pill: leading keeps its width and starts at the system bar's 21pt inset")
    func legacyPill_leading() {
        let leading = HomeTabView.legacyPillInsets(for: .leading)
        let centred = HomeTabView.legacyPillInsets(for: .center)
        #expect(leading.leading == 21)
        #expect(leading.leading + leading.trailing == centred.leading + centred.trailing)
    }

    @Test("legacy pill: Groups and Money draw the pill on the same frame, in each alignment", arguments: [HorizontalAlignment.center, .leading])
    func legacyPill_sameFrameOnBothTabs(alignment: HorizontalAlignment) async throws {
        let pill = PillState(selection: .chat, alignment: alignment)
        let host = HostedPill(state: pill)
        defer { host.close() }

        let groups = try await host.settledFrame()
        pill.selection = .wallet
        let money = try await host.settledFrame()

        #expect(Self.same(groups, money), "Groups \(groups), Money \(money)")
        #expect(abs(groups.width - 318) <= 0.5, "pill \(groups)")
        #expect(abs(groups.minX - (alignment == .leading ? 21 : 42)) <= 0.5, "pill \(groups)")
    }

    // MARK: - Helpers

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 0.5 && abs(a.minY - b.minY) <= 0.5
            && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
    }
}

// MARK: - Hosted bar -

/// The legacy pill's selection and alignment, changed by a test while the pill stays hosted.
@Observable
private final class PillState {
    var selection: HomeTab
    var alignment: HorizontalAlignment
    var frame: CGRect = .zero

    init(selection: HomeTab, alignment: HorizontalAlignment) {
        self.selection = selection
        self.alignment = alignment
    }
}

/// The Group Money shell's legacy pill, with the shell's side margins, at the bottom of a
/// 402pt-wide window. `HomeTabView` draws it only before iOS 26, so the pill is hosted on its own.
@MainActor
private struct HostedPill {
    let window: UIWindow
    let state: PillState

    init(state: PillState) {
        let view = PillScreen(state: state)
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

    /// The pill's frame in the window once two reads 100ms apart agree.
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

    private struct PillScreen: View {
        let state: PillState

        var body: some View {
            VStack {
                Spacer()
                HomeTabBar(selection: Binding { state.selection } set: { state.selection = $0 }, layout: .groupMoney)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.frame = $0 }
                    .padding(HomeTabView.legacyPillInsets(for: state.alignment))
            }
        }
    }
}

/// The two gates the bar reads, flipped by a test while one view stays hosted. Reading them
/// inside a view's body tracks them, so a flip redraws the view as a stored flag change would.
@Observable
private final class BarFlags {
    var showsGroupMoney: Bool
    var leftAligned: Bool

    init(showsGroupMoney: Bool, leftAligned: Bool) {
        self.showsGroupMoney = showsGroupMoney
        self.leftAligned = leftAligned
    }
}

/// Answers the shell's gate and the alignment flag from ``BarFlags`` without touching the stored
/// flags, which other suites read from `UserDefaults.standard` while this one runs.
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
        option == .leftAlignedTabBar ? state.leftAligned : super.hasEnabled(option)
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

        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                guard let bar = Self.tabBar(in: window),
                      let itemCount = bar.items?.count, itemCount >= 2,
                      TabBarItemLocator.itemFrames(in: bar).count == itemCount
                else { return false }
                return true
            }
        } catch {
            let bar = Self.tabBar(in: window)
            Issue.record("bar items: \(bar?.items?.map { $0.title ?? "-" } ?? []), frames: \(bar.map(TabBarItemLocator.itemFrames(in:)) ?? [])")
            window.isHidden = true
            throw error
        }
    }

    func close() {
        window.isHidden = true
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

    /// The union of the bar's items once `selected` is the selected item and the frames have settled.
    func settledItems(selected: String) async throws -> CGRect {
        do {
            try await waitUntil(timeout: .seconds(30)) {
                window.layoutIfNeeded()
                return visibleBar()?.selectedItem?.title == selected
            }
        } catch {
            Issue.record("selected \(visibleBar()?.selectedItem?.title ?? "-"), wanted \(selected)")
            throw error
        }
        let frames = try await settledFrames()
        return frames.dropFirst().reduce(frames[0]) { $0.union($1) }
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar, !bar.isHidden { return bar }
        for subview in view.subviews {
            if let bar = tabBar(in: subview) { return bar }
        }
        return nil
    }
}
