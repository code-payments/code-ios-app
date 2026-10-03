//
//  AttachMenu.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// A row of the composer's attach menu.
enum AttachMenuItem: Equatable {
    case cash
    case camera
    case photos

    /// Returns the menu's rows, top to bottom: Cash wherever Send Cash is offered, then Camera and
    /// Photos while the chat accepts media and the composer has room for another photo.
    static func items(showsCash: Bool, acceptsMedia: Bool, attachedCount: Int) -> [AttachMenuItem] {
        var items: [AttachMenuItem] = []
        if showsCash {
            items.append(.cash)
        }
        if acceptsMedia, attachedCount < ComposerModel.maxAttachments {
            items.append(.camera)
            items.append(.photos)
        }
        return items
    }

    /// Returns how many photos the picker may add to the `attachedCount` already staged.
    static func photosSelectionLimit(attachedCount: Int) -> Int {
        max(0, ComposerModel.maxAttachments - attachedCount)
    }
}

/// The composer's leading `+` control, in the slot Send Cash takes before the chat exists. Opens the
/// attach surface — the floating glass menu of Cash, Camera, and Photos, which grows out of `+` over
/// the field and collapses back into it — and reports where it is laid out, for the surface to grow
/// from. The surface itself is ``AttachSurface``, drawn by the bar or over the keyboard.
struct AttachMenu: View {

    let items: [AttachMenuItem]
    let panel: AttachPanel
    /// Whether `+` is hidden under the camera or photo card.
    let hidesButton: Bool
    /// Whether the attach surface is drawn in `+`'s place, which hides `+`.
    var isStoodInFor = false
    /// Fired as the panel opens, before it is drawn: the keyboard goes down and the panel rides the bar
    /// down with it, or the panel goes up over the keyboard.
    let onOpen: ([AttachMenuItem]) -> Void
    /// Receives `+`'s frame in window coordinates as it is laid out.
    var onPlusFrame: (CGRect) -> Void = { _ in }

    var body: some View {
        Button {
            if !panel.isOpen {
                onOpen(items)
            }
            panel.animate { $0.toggle() }
        } label: {
            Image(systemName: SystemSymbol.plus.rawValue)
                .font(.default(size: 20, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .frame(width: BarMetrics.contentHeight, height: BarMetrics.contentHeight)
                .contentShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        }
        .buttonStyle(.plain)
        .glassBackground(cornerRadius: BarMetrics.cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        .accessibilityLabel("Attach")
        .accessibilityValue(panel.isOpen ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("attach-menu-button")
        .hiddenUnderAttachCard(hidesButton)
        // Fades under the surface growing over it, whose glass can land a frame after `+` would
        // vanish; comes back at once under the surface that has shrunk into it.
        .opacity(isStoodInFor ? 0 : 1)
        .animation(isStoodInFor ? ChatMotion.attachContentOut : nil, value: isStoodInFor)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { onPlusFrame($0) }
        // An edit or a gate taking the slot takes the panel with it.
        .onDisappear { panel.dismiss() }
    }
}

extension AttachPanel {

    /// Acts on the row `item`: Cash collapses the panel, and Camera and Photos expand it into their
    /// card once `warmUp` has the card's content ready, or has waited as long as it will.
    func select(
        _ item: AttachMenuItem,
        warmUp: AttachWarmUp,
        onCash: () -> Void,
        onCamera: @escaping () -> Void,
        onPhotos: @escaping () -> Void
    ) {
        switch item {
        case .cash:
            animate { $0.dismiss() }
            onCash()
        case .camera:
            warmUp.whenReady(for: .camera) { [weak self] in self?.expand(into: onCamera) }
        case .photos:
            warmUp.whenReady(for: .photos) { [weak self] in self?.expand(into: onPhotos) }
        }
    }

    /// Expands the panel into the card `open` puts up: one transaction, so the surface springs from
    /// the menu's frame to the card's while the rows fade out and the card's content in.
    private func expand(into open: () -> Void) {
        guard isOpen else { return }
        withAnimation(ChatMotion.attachCard.animation, completionCriteria: .logicallyComplete) {
            dismiss()
            open()
        } completion: { [weak self] in
            self?.exitDidFinish()
        }
    }
}

/// Takes the attach panel down at the first touch outside it: over the transcript, and over the
/// field beside `+`. Hidden from VoiceOver, which dismisses with the escape gesture instead.
struct AttachPanelDismissArea: View {

    let panel: AttachPanel

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            // A drag from zero rather than a tap, so the touch that starts a scroll dismisses too
            // instead of being swallowed.
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                panel.animate { $0.dismiss() }
            })
            .accessibilityHidden(true)
    }
}

/// The attach menu's rows, top to bottom, laid out at the menu's width. The surface they sit on is
/// ``AttachSurface``'s.
struct AttachMenuRows: View {

    let items: [AttachMenuItem]
    let onSelect: (AttachMenuItem) -> Void
    /// Fired by the escape gesture.
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .labelStyle(AttachMenuRowLabelStyle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AttachSurfaceLayout.menuVerticalPadding)
        .frame(width: AttachSurfaceLayout.menuWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
        .accessibilityIdentifier("attach-menu-panel")
    }
}

/// A panel row: the glyph in a tinted disc so the titles line up, and the whole row the target.
private struct AttachMenuRowLabelStyle: LabelStyle {

    private static let iconDiameter: CGFloat = 42

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
                .font(.default(size: 19, weight: .medium))
                .frame(width: Self.iconDiameter, height: Self.iconDiameter)
                .background(Color.white.opacity(0.08), in: Circle())
            configuration.title
                .font(.default(size: 18, weight: .regular))
        }
        .foregroundStyle(Color.textMain)
        .padding(.horizontal, 18)
        .frame(minHeight: AttachSurfaceLayout.menuRowHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension AttachMenuItem {

    /// The row's title, which is also its VoiceOver label.
    var title: String {
        switch self {
        case .cash:     "Cash"
        case .camera:   "Camera"
        case .photos:   "Photos"
        }
    }

    /// The row's SF Symbol.
    var systemImage: String {
        switch self {
        case .cash:     "banknote"
        case .camera:   "camera"
        case .photos:   "photo.on.rectangle"
        }
    }
}

/// Decides whether a chat offers Camera and Photos.
enum ChatMediaGate {

    /// True for any chat this device has a record of: an encrypted DM's photos are encrypted for it,
    /// a plaintext chat's go up in plaintext. False while the record is still loading.
    static func acceptsMedia(_ conversation: Conversation?) -> Bool {
        conversation != nil
    }
}
