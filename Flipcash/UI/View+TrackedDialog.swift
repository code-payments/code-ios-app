//
//  View+TrackedDialog.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

extension View {
    /// `.dialog(item:)` with automatic `Error Modal Displayed` tracking for
    /// items whose `tracked` flag is true (i.e. created via `DialogItem.error`).
    /// `Screen` is sourced from `AppRouter.currentScreenName` via the SwiftUI
    /// environment. Use this wrapper for every dialog binding in the Flipcash
    /// app target — `.dialog(item:)` directly would skip tracking.
    func trackedDialog(
        item: Binding<DialogItem?>,
        callSite: String? = nil
    ) -> some View {
        modifier(TrackedDialogModifier(item: item, callSite: callSite))
    }
}

private struct TrackedDialogModifier: ViewModifier {

    let item: Binding<DialogItem?>
    let callSite: String?
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.dialog(item: item) { presented in
            // DialogItem factories all require non-optional title/subtitle, so
            // these fall-throughs are defensive against a future raw-init
            // caller that passes nil.
            guard presented.tracked, let title = presented.title, let subtitle = presented.subtitle else { return }
            Analytics.errorModalDisplayed(
                title: title,
                message: subtitle,
                screen: router.currentScreenName,
                callSite: callSite
            )
        }
    }
}
