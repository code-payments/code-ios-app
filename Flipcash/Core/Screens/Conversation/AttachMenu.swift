//
//  AttachMenu.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import SwiftUI
import FlipcashUI

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

/// The composer's leading `+` control: a menu of Cash, Camera, and Photos, in the slot Send Cash
/// takes before the chat exists.
///
/// Photos opens the system picker, which runs out of process and needs no library permission —
/// the same reason ``GalleryScanButton`` uses it.
struct AttachMenu: View {

    let items: [AttachMenuItem]
    /// The most photos one pick may return, so the strip never passes `ComposerModel.maxAttachments`.
    let photosSelectionLimit: Int
    let onCash: () -> Void
    let onCamera: () -> Void
    /// Receives the picked photos in the order they were selected.
    let onPhotos: ([PhotosPickerItem]) -> Void

    @State private var isPickingPhotos = false
    @State private var pickedPhotos: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            ForEach(items, id: \.self) { item in
                switch item {
                case .cash:
                    Button("Cash", systemImage: "banknote", action: onCash)
                case .camera:
                    Button("Camera", systemImage: "camera", action: onCamera)
                case .photos:
                    // Presented from the modifier below rather than as a `PhotosPicker` row: a
                    // picker nested in a `Menu` is torn down with the menu before it can present.
                    Button("Photos", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
                }
            }
        } label: {
            Image(systemName: SystemSymbol.plus.rawValue)
                .font(.default(size: 20, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .frame(width: BarMetrics.contentHeight, height: BarMetrics.contentHeight)
                .contentShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        }
        // Declared order, top to bottom. The system otherwise reverses a menu that opens upward,
        // which is every menu raised from the bottom bar.
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .glassBackground(cornerRadius: BarMetrics.cornerRadius)
        .clipShape(RoundedRectangle(cornerRadius: BarMetrics.cornerRadius))
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("attach-menu-button")
        .photosPicker(
            isPresented: $isPickingPhotos,
            selection: $pickedPhotos,
            maxSelectionCount: photosSelectionLimit,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: pickedPhotos) { _, picked in
            guard !picked.isEmpty else { return }
            // Cleared so the next pick starts empty instead of preselecting what was just staged.
            pickedPhotos = []
            onPhotos(picked)
        }
    }
}
