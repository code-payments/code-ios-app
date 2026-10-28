//
//  TrayMotion.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// Every animation a tray runs, as ``ChatSpring`` values (the house spring model).
///
/// The tray's card is drawn in SwiftUI inside an invisible sheet, so every motion here is ours,
/// the card's height included; the sheet's own edge never animates.
nonisolated enum TrayMotion {

    /// The card's height, and the chrome and page with it, as a step changes.
    static var resize: ChatSpring { spring("Tray Motion/Resize", 0.35, 0) } // LOCAL-TUNER

    /// The incoming page fading and unblurring into place.
    static var contentIn: ChatSpring { spring("Tray Motion/Content in", 0.27, 0) } // LOCAL-TUNER

    /// The outgoing page clearing; quicker than the entrance so the two never read as a muddle.
    static var contentOut: ChatSpring { spring("Tray Motion/Content out", 0.20, 0) } // LOCAL-TUNER

    /// The action's old title clearing; quicker than the new one arriving.
    static var labelOut: ChatSpring { spring("Tray Label/Out", 0.17, 0) } // LOCAL-TUNER

    /// The action's new title settling into place.
    static var labelIn: ChatSpring { spring("Tray Label/In", 0.34, 0.1) } // LOCAL-TUNER

    /// How long the new title waits, so it lands as the old one clears.
    static var labelInDelay: TimeInterval {
        Tuner.value("Tray Label/In delay", default: 0.045, in: 0...0.2, unit: .seconds) // LOCAL-TUNER
    }

    /// The blur a title carries at either end of its change.
    static var labelBlur: CGFloat {
        Tuner.value("Tray Label/Blur", default: 0, in: 0...10, unit: .points) // LOCAL-TUNER
    }

    /// How far a title travels as it changes: the new one rises into place, the old one rises away.
    static var labelRise: CGFloat {
        Tuner.value("Tray Label/Rise", default: 0, in: 0...20, unit: .points) // LOCAL-TUNER
    }

    /// The scale a title holds at either end of its change.
    static var labelScale: CGFloat {
        Tuner.value("Tray Label/Scale", default: 1, in: 0.8...1) // LOCAL-TUNER
    }

    /// Whether a step back reverses the rise, so the title falls the way the flow went.
    static var labelFollowsDirection: Bool {
        Tuner.value("Tray Label/Follow direction", default: true) // LOCAL-TUNER
    }

    /// How long the incoming page waits, so it lands as the outgoing one clears.
    static var contentInDelay: TimeInterval {
        Tuner.value("Tray Motion/Content in delay", default: 0.05, in: 0...0.3, unit: .seconds) // LOCAL-TUNER
    }

    /// The blur a page carries at either end of its crossfade.
    static var pageBlur: CGFloat {
        Tuner.value("Tray Motion/Page blur", default: 2, in: 0...20, unit: .points) // LOCAL-TUNER
    }

    /// Whether a page scales as it crossfades.
    static var pageScales: Bool {
        Tuner.value("Tray Motion/Page scale", default: true) // LOCAL-TUNER
    }

    /// The scale a leaving page shrinks to.
    static var pageScaleOut: CGFloat {
        Tuner.value("Tray Motion/Scale out", default: 0.96, in: 0.85...1) // LOCAL-TUNER
    }

    /// The scale an arriving page grows from.
    static var pageScaleIn: CGFloat {
        Tuner.value("Tray Motion/Scale in from", default: 0.96, in: 0.85...1) // LOCAL-TUNER
    }

    // Bakes back to `ChatSpring(duration:bounce:)` lets.
    private static func spring(_ key: String, _ duration: TimeInterval, _ bounce: Double) -> ChatSpring {
        let spring = Tuner.value(key, default: Spring(duration: duration, bounce: bounce), form: "ChatSpring(duration: {duration}, bounce: {bounce})") // LOCAL-TUNER
        return ChatSpring(duration: spring.duration, bounce: spring.bounce)
    }
}

extension ChatSpring {
    /// The same spring as SwiftUI's value type, for reading positions along it.
    var spring: Spring { Spring(duration: duration, bounce: bounce) }
}

/// One end of a tray crossfade: faded, blurred, scaled about the centre and shifted.
///
/// A collapsing end stops taking up height at once, without animating, and stops naming the tray:
/// a leaving page then leaves the region to size to the incoming page alone, on the resize spring.
struct TrayFade: ViewModifier {

    static let identity = TrayFade(opacity: 1, blur: 0, scale: 1)

    var opacity: Double
    var blur: CGFloat
    var scale: CGFloat
    var offset: CGFloat = 0
    var collapses = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: .center)
            .offset(y: offset)
            .opacity(opacity)
            .blur(radius: blur)
            .frame(height: collapses ? 0 : nil, alignment: .top)
            .animation(nil, value: collapses)
            .transformPreference(TrayTitleKey.self) { title in
                if collapses { title = nil }
            }
    }
}

extension AnyTransition {

    /// A crossfade that arrives from `insertion` on `insertionAnimation` and leaves for `removal`
    /// on `removalAnimation`.
    static func trayFade(
        insertion: TrayFade,
        insertionAnimation: Animation,
        removal: TrayFade,
        removalAnimation: Animation
    ) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: insertion, identity: .identity).animation(insertionAnimation),
            removal: .modifier(active: removal, identity: .identity).animation(removalAnimation)
        )
    }
}
