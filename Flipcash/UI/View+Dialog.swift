//
//  View+Dialog.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

extension View {
    /// Presents a `DialogItem` and reports the `Error Modal Displayed`
    /// Mixpanel event for items whose `tracked` flag is true (created via
    /// `DialogItem.error`). `Screen` is derived from the topmost presented
    /// sheet (`AppRouter.presentedSheet?.description`), falling back to
    /// `"scan"` when no sheet is up — the same string used in router logs.
    ///
    /// This overload lives in the Flipcash app target (not FlipcashUI)
    /// because firing analytics requires the app-target Analytics namespace.
    /// The Boolean and generic `T: Identifiable` overloads of `.dialog(...)`
    /// remain in FlipcashUI.
    func dialog(item: Binding<DialogItem?>) -> some View {
        modifier(DialogItemModifier(item: item))
    }
}

private struct DialogItemModifier: ViewModifier {

    let item: Binding<DialogItem?>
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .sheet(item: item) { presented in
                PartialSheet(background: presented.style.backgroundColor, canDismiss: presented.dismissable) {
                    Dialog(
                        style: presented.style,
                        title: presented.title,
                        subtitle: presented.subtitle,
                        dismiss: dismiss,
                        actions: presented.actions
                    )
                    .onAppear {
                        // Factories require non-optional title/subtitle; the
                        // guard-lets are defensive against a future raw-init
                        // caller passing nil.
                        guard presented.tracked,
                              let title = presented.title,
                              let subtitle = presented.subtitle else { return }
                        Analytics.errorModalDisplayed(
                            title: title,
                            message: subtitle,
                            screen: router.presentedSheet?.description ?? "scan",
                            callSite: nil
                        )
                    }
                }
            }
    }

    private func dismiss() {
        item.wrappedValue = nil
    }
}
