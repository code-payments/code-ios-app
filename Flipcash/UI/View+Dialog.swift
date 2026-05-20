//
//  View+Dialog.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

extension View {
    /// Presents a `DialogItem`, reporting an analytics event for tracked items.
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
