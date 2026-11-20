//
//  ShellTabSwitch.swift
//  Flipcash
//

import SwiftUI

/// A switch between the Group Money shell's two bar tabs, while the tab switched to fades its
/// header in over the header of the tab it left.
struct ShellTabSwitch: Equatable {
    let from: HomeTab
    let to: HomeTab
    let id = UUID()

    /// How long the headers take to fade, in seconds, matching Android's whole-screen tab fade.
    static let duration: TimeInterval = 0.3

    /// How far a fade that began at `start` has run at `date`: 0 at its start, 1 once it is done.
    static func progress(since start: Date, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(start) / duration
        return UnitCurve.easeInOut.value(at: min(max(elapsed, 0), 1))
    }
}

extension EnvironmentValues {
    /// The bar-tab switch whose header fade is running, nil when none is. Set by `HomeTabView`
    /// on iOS 26 with the Group Money shell, where the system swaps tabs without a fade.
    @Entry var shellTabSwitch: ShellTabSwitch? = nil
}

/// One of a shell tab's header items: `content`, and while a switch into `tab` runs, the item the
/// tab switched from drew in the same slot, fading out as `content` fades in.
///
/// The copy is drawn only. It takes no touches, is not in the accessibility tree, and leaves the
/// hierarchy when the fade is done.
struct ShellHeaderCrossfade<Content: View, Outgoing: View>: View {
    let tab: HomeTab
    let alignment: Alignment
    @ViewBuilder let content: Content
    @ViewBuilder let outgoing: (HomeTab) -> Outgoing

    @Environment(\.shellTabSwitch) private var tabSwitch

    /// When this item's fade began: the first update that saw the switch. Later than the switch
    /// the first time a tab comes forward, when the system builds its bar items only then, so
    /// those items still run the whole fade. Read from the clock rather than animated, because
    /// an animation started before the item is on screen ends before it is.
    @State private var fadeStart: (id: UUID, date: Date)?

    private var arriving: ShellTabSwitch? {
        guard let tabSwitch, tabSwitch.to == tab, tabSwitch.from != tab else { return nil }
        return tabSwitch
    }

    var body: some View {
        // In place with no switch too, paused, so `content` keeps its identity across one.
        TimelineView(.animation(paused: arriving == nil)) { context in
            let shown = shownFraction(at: context.date)
            content
                .opacity(shown)
                // Over `content` rather than beside it, so the item keeps its size and the bar's
                // glass around it does not grow for the fade.
                .overlay(alignment: alignment) {
                    if let arriving, shown < 1 {
                        outgoing(arriving.from)
                            .fixedSize()
                            .opacity(1 - shown)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .onChange(of: arriving?.id, initial: true) { _, id in
            fadeStart = id.map { ($0, .now) }
        }
    }

    /// How much of `content` shows at `date`, the copy showing the rest.
    private func shownFraction(at date: Date) -> Double {
        guard let arriving else { return 1 }
        // The update that brings the switch draws the copy alone; the fade starts from there.
        guard let fadeStart, fadeStart.id == arriving.id else { return 0 }
        return ShellTabSwitch.progress(since: fadeStart.date, at: date)
    }
}
