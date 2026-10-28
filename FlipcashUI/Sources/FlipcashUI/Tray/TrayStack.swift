//
//  TrayStack.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// A multi-step tray: the card around the page for its flow's current step, with the icon, the
/// X and the actions.
///
/// Only the page swaps between steps, blur-crossfading in place, while the card resizes on one
/// spring with its content and actions, so the actions hold still on screen. The X goes back a
/// step from the second step on and dismisses on the root, where it is hidden for a tray
/// presented with `isDismissable: false`.
public struct TrayStack<Step: Hashable, Page: View>: View {

    private let flow: TrayFlow<Step>
    private let icon: (Step) -> TrayIcon?
    private let headerTitle: (Step) -> String?
    /// Whether the icon was given per step; one icon for the whole flow never swaps.
    private var iconVaries = true
    private let style: TrayStyle
    private let actions: (Step) -> [TrayAction]
    private let page: (Step) -> Page

    @State private var title: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.trayIsDismissable) private var isDismissable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a tray for `flow`, with `actions` and a `page` (a ``TrayPage``) for each step.
    public init(
        flow: TrayFlow<Step>,
        icon: TrayIcon? = nil,
        style: TrayStyle = .standard,
        actions: @escaping (Step) -> [TrayAction],
        @ViewBuilder page: @escaping (Step) -> Page
    ) {
        self.init(flow: flow, icon: { _ in icon }, headerTitle: { _ in nil }, style: style, actions: actions, page: page)
        iconVaries = false
    }

    /// Creates a tray whose icon can change or drop away per step, such as a keypad step that
    /// needs the height; a change of icon crossfades with the page, and no icon closes its space.
    /// A step with no icon and a `headerTitle` shows that title in the icon's corner, level with
    /// the X, over a page made with ``TrayPage/init(content:)``.
    public init(
        flow: TrayFlow<Step>,
        icon: @escaping (Step) -> TrayIcon?,
        headerTitle: @escaping (Step) -> String? = { _ in nil },
        style: TrayStyle = .standard,
        actions: @escaping (Step) -> [TrayAction],
        @ViewBuilder page: @escaping (Step) -> Page
    ) {
        self.flow = flow
        self.icon = icon
        self.headerTitle = headerTitle
        self.style = style
        self.actions = actions
        self.page = page
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ZStack(alignment: .topLeading) {
                page(flow.current)
                    .id(flow.current)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Pages fading in and out move with the region as the tray resizes, not on their own.
            .geometryGroup()
            .padding(.top, TrayMetrics.iconToTitle)
            // VoiceOver reads the title first, then the actions, then the X.
            .accessibilitySortPriority(3)

            // A tray whose content is its own set of choices has no bar.
            if !actions(flow.current).isEmpty {
                TrayActionBar(actions: actions(flow.current), movesForward: flow.direction == .forward)
                    .padding(.top, TrayMetrics.contentToActions)
                    .accessibilitySortPriority(2)
            }
        }
        .padding(TrayMetrics.padding)
        // Inside the resize animation with the content: outside it, the surface snaps to the new
        // height while the content springs.
        .background { TrayFill(style: style) }
        .animation(TrayMotion.resize.animation, value: flow.path)
        .onPreferenceChange(TrayTitleKey.self) { title = $0 }
        // UI tests find a dialog by its title, and the tray stands in for dialogs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(title ?? headerTitle(flow.current) ?? "Tray")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let icon = icon(flow.current) {
                    TrayIconView(icon: icon, color: style.iconColor)
                        // The same icon on the next step stays put; only a change swaps it.
                        .id(iconVaries ? icon.identity ?? AnyHashable(flow.current) : nil)
                        .transition(pageTransition)
                } else if let title = headerTitle(flow.current) {
                    Text(title)
                        // SF Pro until type tokens are decided (Phase 2).
                        .font(.system(size: TrayMetrics.scaled(TrayMetrics.headerTitleSize, .headline, dynamicTypeSize), weight: TrayMetrics.titleWeight))
                        .tracking(TrayMetrics.titleTracking)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .frame(minHeight: TrayMetrics.closeSize, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        // The same title on the next step stays put; a new one crossfades in place.
                        .id("title:" + title)
                        .transition(headerTitleTransition)
                }
            }
            // An icon or title fading in or out rides the card's moving top edge with the rest of
            // the header, as the pages do, instead of standing at its own ends of the resize.
            .geometryGroup()
            Spacer(minLength: 0)
            closeButton
        }
    }

    private var closeButton: some View {
        let isVisible = flow.canGoBack || isDismissable
        return TrayCloseButton(accessibilityLabel: flow.canGoBack ? "Back" : "Close") {
            flow.close { dismiss() }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .accessibilitySortPriority(1)
    }

    // MARK: - Transitions

    /// A header title swaps by fading alone, on the page's timing, so it reads as the same line.
    private var headerTitleTransition: AnyTransition {
        .trayFade(
            insertion: TrayFade(opacity: 0, blur: 0, scale: 1),
            insertionAnimation: TrayMotion.contentIn.animation.delay(TrayMotion.contentInDelay),
            removal: TrayFade(opacity: 0, blur: 0, scale: 1),
            removalAnimation: TrayMotion.contentOut.animation
        )
    }

    // Reduce Motion keeps the fade and drops the blur and scale.
    private var pageTransition: AnyTransition {
        let blur = reduceMotion ? 0 : TrayMotion.pageBlur
        let scales = TrayMotion.pageScales && !reduceMotion
        return .trayFade(
            insertion: TrayFade(opacity: 0, blur: blur, scale: scales ? TrayMotion.pageScaleIn : 1),
            insertionAnimation: TrayMotion.contentIn.animation.delay(TrayMotion.contentInDelay),
            removal: TrayFade(opacity: 0, blur: blur, scale: scales ? TrayMotion.pageScaleOut : 1, collapses: true),
            removalAnimation: TrayMotion.contentOut.animation
        )
    }
}

/// A single-step tray: an optional icon, the X, a title and message, optional content, and one
/// or two actions.
public struct Tray<Content: View>: View {

    private let title: String
    private let message: String?
    private let icon: TrayIcon?
    private let style: TrayStyle
    private let actions: [TrayAction]
    private let content: Content?

    @State private var flow = TrayFlow(root: SingleStep.only)

    /// Creates a tray with `content` under the title and message.
    public init(
        title: String,
        message: String? = nil,
        icon: TrayIcon? = nil,
        style: TrayStyle = .standard,
        actions: [TrayAction],
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, message: message, icon: icon, style: style, actions: actions, content: content())
    }

    /// Creates a tray whose content may be absent.
    private init(title: String, message: String?, icon: TrayIcon?, style: TrayStyle, actions: [TrayAction], content: Content?) {
        self.title = title
        self.message = message
        self.icon = icon
        self.style = style
        self.actions = actions
        self.content = content
    }

    public var body: some View {
        TrayStack(flow: flow, icon: { _ in icon }, style: style, actions: { _ in actions }) { _ in
            TrayPage(title: title, message: message, content: content)
        }
    }

    private enum SingleStep: Hashable {
        case only
    }
}

extension Tray where Content == EmptyView {

    /// Creates a tray of a title, an optional message and its actions.
    public init(
        title: String,
        message: String? = nil,
        icon: TrayIcon? = nil,
        style: TrayStyle = .standard,
        actions: [TrayAction]
    ) {
        self.init(title: title, message: message, icon: icon, style: style, actions: actions, content: nil)
    }
}

extension EnvironmentValues {
    /// Whether the presented tray can be dismissed; set by `.tray(…)`.
    @Entry var trayIsDismissable = true
}
