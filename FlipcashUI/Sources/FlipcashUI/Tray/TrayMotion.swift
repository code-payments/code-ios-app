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
    static let resize = ChatSpring(duration: 0.35, bounce: 0)

    /// The incoming page fading and unblurring into place.
    static let contentIn = ChatSpring(duration: 0.27, bounce: 0)

    /// The outgoing page clearing; quicker than the entrance so the two never read as a muddle.
    static let contentOut = ChatSpring(duration: 0.20, bounce: 0)

    /// The action's old title clearing; quicker than the new one arriving.
    static let labelOut = ChatSpring(duration: 0.17, bounce: 0)

    /// The action's new title settling into place.
    static let labelIn = ChatSpring(duration: 0.34, bounce: 0.1)

    /// How long the new title waits, so it lands as the old one clears.
    static let labelInDelay: TimeInterval = 0.045

    /// The blur a title carries at either end of its change.
    static let labelBlur: CGFloat = 0

    /// How far a title travels as it changes: the new one rises into place, the old one rises away.
    static let labelRise: CGFloat = 0

    /// The scale a title holds at either end of its change.
    static let labelScale: CGFloat = 1

    /// Whether a step back reverses the rise, so the title falls the way the flow went.
    static let labelFollowsDirection = true

    /// How long the incoming page waits, so it lands as the outgoing one clears.
    static let contentInDelay: TimeInterval = 0.05

    /// The blur a page carries at either end of its crossfade.
    static let pageBlur: CGFloat = 2

    /// Whether a page scales as it crossfades.
    static let pageScales = true

    /// The scale a leaving page shrinks to.
    static let pageScaleOut: CGFloat = 0.96

    /// The scale an arriving page grows from.
    static let pageScaleIn: CGFloat = 0.96
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
