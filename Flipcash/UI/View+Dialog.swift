//
//  View+Dialog.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

extension View {
    /// Presents a `DialogItem`, reporting an analytics event for tracked items.
    @ViewBuilder // LOCAL-TUNER
    func dialog(item: Binding<DialogItem?>) -> some View {
        if DialogTrayModifier.isOn { modifier(DialogTrayModifier(item: item)) } else { // LOCAL-TUNER
        modifier(DialogItemModifier(item: item))
        } // LOCAL-TUNER
    }
}

private struct DialogItemModifier: ViewModifier {

    let item: Binding<DialogItem?>
    @Environment(AppRouter.self) private var router: AppRouter?

    /// Captured while the dialog is up so its `onDismiss` still fires when the
    /// scrim tap clears the binding before `onDismiss` runs.
    @State private var pendingDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(item: item, onDismiss: runPendingDismiss) { presented in
                PartialSheet(background: presented.style.backgroundColor, canDismiss: presented.dismissable) {
                    Dialog(
                        style: presented.style,
                        title: presented.title,
                        subtitle: presented.subtitle,
                        checkbox: presented.checkbox,
                        dismiss: dismiss,
                        actions: presented.actions
                    )
                    .onAppear {
                        pendingDismiss = presented.onDismiss
                        guard presented.tracked,
                              let title = presented.title,
                              let subtitle = presented.subtitle else { return }
                        Analytics.errorModalDisplayed(
                            title: title,
                            message: subtitle,
                            screen: router?.presentedSheet?.description ?? "scan",
                            callSite: nil
                        )
                    }
                }
            }
    }

    private func dismiss() {
        item.wrappedValue = nil
    }

    private func runPendingDismiss() {
        pendingDismiss?()
        pendingDismiss = nil
    }
}

/// Presents a `DialogItem` as a tray: the same title, subtitle, style, dismissability, actions, // LOCAL-TUNER
/// analytics and `onDismiss` as the dialog, with an icon for the error and success styles. // LOCAL-TUNER
private struct DialogTrayModifier: ViewModifier { // LOCAL-TUNER

    /// Whether dialogs show as trays; the tuner's "Tray Behavior/Dialogs as trays". // LOCAL-TUNER
    @MainActor static var isOn: Bool { Tuner.shared.value("Tray Behavior/Dialogs as trays", default: true) } // LOCAL-TUNER

    let item: Binding<DialogItem?> // LOCAL-TUNER
    @Environment(AppRouter.self) private var router: AppRouter? // LOCAL-TUNER

    /// Captured while the tray is up so its `onDismiss` still fires when a drag clears the binding. // LOCAL-TUNER
    @State private var pendingDismiss: (() -> Void)? // LOCAL-TUNER

    func body(content: Content) -> some View { // LOCAL-TUNER
        content // LOCAL-TUNER
            .tray(item: item, isDismissable: item.wrappedValue?.dismissable ?? true, onDismiss: runPendingDismiss) { presented in // LOCAL-TUNER
                DialogTray(item: presented, dismiss: dismiss) // LOCAL-TUNER
                    .onAppear { // LOCAL-TUNER
                        pendingDismiss = presented.onDismiss // LOCAL-TUNER
                        guard presented.tracked, // LOCAL-TUNER
                              let title = presented.title, // LOCAL-TUNER
                              let subtitle = presented.subtitle else { return } // LOCAL-TUNER
                        Analytics.errorModalDisplayed( // LOCAL-TUNER
                            title: title, // LOCAL-TUNER
                            message: subtitle, // LOCAL-TUNER
                            screen: router?.presentedSheet?.description ?? "scan", // LOCAL-TUNER
                            callSite: nil // LOCAL-TUNER
                        ) // LOCAL-TUNER
                    } // LOCAL-TUNER
            } // LOCAL-TUNER
    } // LOCAL-TUNER

    private func dismiss() { // LOCAL-TUNER
        item.wrappedValue = nil // LOCAL-TUNER
    } // LOCAL-TUNER

    private func runPendingDismiss() { // LOCAL-TUNER
        pendingDismiss?() // LOCAL-TUNER
        pendingDismiss = nil // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER

/// A `DialogItem` drawn as a single-step tray, its checkbox as the tray's content. // LOCAL-TUNER
private struct DialogTray: View { // LOCAL-TUNER

    let item: DialogItem // LOCAL-TUNER
    let dismiss: () -> Void // LOCAL-TUNER

    @State private var isChecked = false // LOCAL-TUNER

    var body: some View { // LOCAL-TUNER
        if let checkbox = item.checkbox { // LOCAL-TUNER
            Tray(title: item.title ?? "", message: item.subtitle, icon: icon, style: style, actions: actions) { // LOCAL-TUNER
                checkboxRow(checkbox) // LOCAL-TUNER
            } // LOCAL-TUNER
        } else { // LOCAL-TUNER
            Tray(title: item.title ?? "", message: item.subtitle, icon: icon, style: style, actions: actions) // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    private var style: TrayStyle { // LOCAL-TUNER
        switch item.style { // LOCAL-TUNER
        case .standard: .standard // LOCAL-TUNER
        case .success: .success // LOCAL-TUNER
        case .destructive: .error // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    private var icon: TrayIcon? { // LOCAL-TUNER
        switch item.style { // LOCAL-TUNER
        case .standard: nil // LOCAL-TUNER
        case .success: .central(.circleCheck) // LOCAL-TUNER
        case .destructive: .destructive // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    /// The dialog's actions as tray actions, each dismissing before it runs as the dialog's do. // LOCAL-TUNER
    /// A second action that would share the first one's place takes the secondary's. // LOCAL-TUNER
    private var actions: [TrayAction] { // LOCAL-TUNER
        var taken: Set<Int> = [] // LOCAL-TUNER
        return item.actions.map { action in // LOCAL-TUNER
            // A lone destructive action is the red dialog's OK, not a warning. // LOCAL-TUNER
            var role = item.actions.count == 1 ? .primary : Self.role(for: action.kind) // LOCAL-TUNER
            let slot = role == .secondary ? 0 : 1 // LOCAL-TUNER
            if taken.contains(slot) { // LOCAL-TUNER
                role = slot == 0 ? .primary : .secondary // LOCAL-TUNER
            } // LOCAL-TUNER
            taken.insert(role == .secondary ? 0 : 1) // LOCAL-TUNER
            return TrayAction(action.title, role: role) { // LOCAL-TUNER
                dismiss() // LOCAL-TUNER
                action.perform(isChecked: isChecked) // LOCAL-TUNER
            } // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    private static func role(for kind: DialogAction.Kind) -> TrayAction.Role { // LOCAL-TUNER
        switch kind { // LOCAL-TUNER
        case .standard: .primary // LOCAL-TUNER
        case .destructive: .destructive // LOCAL-TUNER
        case .subtle, .outline: .secondary // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER

    private func checkboxRow(_ checkbox: DialogCheckbox) -> some View { // LOCAL-TUNER
        Button { // LOCAL-TUNER
            isChecked.toggle() // LOCAL-TUNER
        } label: { // LOCAL-TUNER
            HStack(spacing: 10) { // LOCAL-TUNER
                Image(systemName: isChecked ? "checkmark.square.fill" : "square") // LOCAL-TUNER
                    .font(.system(size: 20)) // LOCAL-TUNER
                Text(checkbox.label) // LOCAL-TUNER
                    .font(.default(size: 14, weight: .medium)) // LOCAL-TUNER
                    .frame(maxWidth: .infinity, alignment: .leading) // LOCAL-TUNER
            } // LOCAL-TUNER
            .contentShape(Rectangle()) // LOCAL-TUNER
            .padding(.vertical, 8) // LOCAL-TUNER
        } // LOCAL-TUNER
        .buttonStyle(.plain) // LOCAL-TUNER
        .foregroundStyle(Color.textMain) // LOCAL-TUNER
        .accessibilityAddTraits(isChecked ? .isSelected : []) // LOCAL-TUNER
        .accessibilityIdentifier("dialog-checkbox") // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER
