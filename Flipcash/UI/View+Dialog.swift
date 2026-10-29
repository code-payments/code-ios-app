//
//  View+Dialog.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

extension View {
    /// Presents a `DialogItem` as a tray, reporting an analytics event for tracked items.
    func dialog(item: Binding<DialogItem?>) -> some View {
        modifier(DialogTrayModifier(item: item))
    }
}

/// Presents a `DialogItem` as a tray: its title, subtitle, style, dismissability, actions,
/// analytics and `onDismiss`, with an icon for the error and success styles.
private struct DialogTrayModifier: ViewModifier {

    let item: Binding<DialogItem?>
    @Environment(AppRouter.self) private var router: AppRouter?

    /// Captured while the tray is up so its `onDismiss` still fires when a drag clears the binding.
    @State private var pendingDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .tray(item: item, isDismissable: item.wrappedValue?.dismissable ?? true, onDismiss: runPendingDismiss) { presented in
                DialogTray(item: presented, dismiss: dismiss)
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

    private func dismiss() {
        item.wrappedValue = nil
    }

    private func runPendingDismiss() {
        pendingDismiss?()
        pendingDismiss = nil
    }
}

/// A `DialogItem` drawn as a single-step tray, its checkbox as the tray's content.
private struct DialogTray: View {

    let item: DialogItem
    let dismiss: () -> Void

    @State private var isChecked = false

    var body: some View {
        if let checkbox = item.checkbox {
            Tray(title: item.title ?? "", message: item.subtitle, icon: icon, style: style, actions: actions) {
                checkboxRow(checkbox)
            }
        } else {
            Tray(title: item.title ?? "", message: item.subtitle, icon: icon, style: style, actions: actions)
        }
    }

    private var style: TrayStyle {
        switch item.style {
        case .standard: .standard
        case .success: .success
        case .destructive: .error
        }
    }

    private var icon: TrayIcon? {
        switch item.style {
        case .standard: nil
        case .success: .central(.circleCheck)
        case .destructive: .destructive
        }
    }

    /// The dialog's actions as tray actions, each dismissing before it runs as the dialog's do.
    /// A second action that would share the first one's place takes the secondary's.
    private var actions: [TrayAction] {
        var taken: Set<Int> = []
        return item.actions.map { action in
            // A lone destructive action is the red dialog's OK, not a warning.
            var role = item.actions.count == 1 ? .primary : Self.role(for: action.kind)
            let slot = role == .secondary ? 0 : 1
            if taken.contains(slot) {
                role = slot == 0 ? .primary : .secondary
            }
            taken.insert(role == .secondary ? 0 : 1)
            return TrayAction(action.title, role: role) {
                dismiss()
                action.perform(isChecked: isChecked)
            }
        }
    }

    private static func role(for kind: DialogAction.Kind) -> TrayAction.Role {
        switch kind {
        case .standard: .primary
        case .destructive: .destructive
        case .subtle, .outline: .secondary
        }
    }

    private func checkboxRow(_ checkbox: DialogCheckbox) -> some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                Text(checkbox.label)
                    .font(.default(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textMain)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityIdentifier("dialog-checkbox")
    }
}
