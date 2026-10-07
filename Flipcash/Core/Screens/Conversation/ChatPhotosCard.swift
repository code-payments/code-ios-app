//
//  ChatPhotosCard.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import SwiftUI
import FlipcashUI

/// A photo pick in progress: the selection, in the order it was made, the loader already reading
/// it, and whether the full system picker is up over the card.
///
/// Held by the bar's model rather than the card, so the inline picker can be mounted ahead of the card
/// and a Back or a close without a choice can clear the pick wherever it is drawn.
@MainActor
@Observable
final class AttachPhotosPick {

    var selection: [PhotosPickerItem] = [] {
        didSet { preloader.update(selection: selection) }
    }

    /// Whether the full system picker is up as a sheet over the card.
    var showsLibrary = false

    private(set) var preloader = AttachPhotosPick.makePreloader()

    /// Discards the selection and what was loaded for it.
    func reset() {
        selection = []
        showsLibrary = false
        preloader.reset()
    }

    /// Hands the selection and the loader reading it to `add`, and starts a fresh pick without
    /// cancelling what that loader is still reading.
    func handOff(to add: ([PhotosPickerItem], ChatPhotoPreloader<PhotosPickerItem>) -> Void) {
        let selection = selection
        let preloader = preloader
        self.preloader = Self.makePreloader()
        self.selection = []
        showsLibrary = false
        add(selection, preloader)
    }

    private static func makePreloader() -> ChatPhotoPreloader<PhotosPickerItem> {
        ChatPhotoPreloader(load: ChatPhotoStaging.loadImage)
    }
}

/// The attach menu's Photos: the system photo picker inline, with a back chevron and, bottom right,
/// All Photos — the full system picker, for albums — until something is selected, then an Add pill.
/// Content of ``AttachSurface``, which draws the card's glass and clip.
///
/// The picker runs out of process and needs no photo library permission. Selecting stages nothing,
/// but starts loading each photo, so it is in hand at Add; the selection is handed over then, in the
/// order it was made.
struct ChatPhotosCard: View {

    let pick: AttachPhotosPick
    /// The most photos one pick may hold, so the strip never passes `ComposerModel.maxAttachments`.
    let selectionLimit: Int
    /// Receives the selection, in the order it was made, with the loader already reading it.
    let onAdd: ([PhotosPickerItem], ChatPhotoPreloader<PhotosPickerItem>) -> Void
    /// Fired by the back chevron and the escape gesture; the host discards the selection.
    let onBack: () -> Void
    /// Fired by All Photos in place of putting the full picker up here, for a card that can't present
    /// a sheet. All Photos only shows with nothing selected, so nothing is lost.
    var onAllPhotos: (() -> Void)? = nil
    /// Whether the full picker comes up as the card appears, for a card All Photos was handed to.
    var opensLibraryOnAppear = false

    /// Reports each tap to the selection as it is made, in order. The picker's own Add is disabled,
    /// and the non-continuous behaviours report only through it.
    static let selectionBehavior: PhotosPickerSelectionBehavior = .continuousAndOrdered

    /// Returns the Add pill's title for `count` selected photos.
    static func addTitle(count: Int) -> String {
        count == 1 ? "Add 1 photo" : "Add \(count) photos"
    }

    var body: some View {
        @Bindable var pick = pick
        PhotosPicker(
            selection: $pick.selection,
            maxSelectionCount: selectionLimit,
            selectionBehavior: Self.selectionBehavior,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Text("Photos")
        }
        .photosPickerStyle(.inline)
        // Hidden at the top too: there it shows a prompt, a Photos/Collections switch, and a privacy
        // banner that take most of the card, and nothing can switch it to Collections from outside.
        // All Photos opens the full picker for albums instead.
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
        .photosPickerDisabledCapabilities(.selectionActions)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            controls
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onBack)
        .accessibilityIdentifier("attach-photos-card")
        // Bound to the same selection, so picks made in either picker show in both.
        .photosPicker(
            isPresented: $pick.showsLibrary,
            selection: $pick.selection,
            maxSelectionCount: selectionLimit,
            selectionBehavior: Self.selectionBehavior,
            matching: .images,
            photoLibrary: .shared()
        )
        // The presented picker takes the app's white root tint, which hides the white number on its selection badges.
        .tint(.blue)
        .onAppear {
            if opensLibraryOnAppear {
                pick.showsLibrary = true
            }
        }
    }

    private var controls: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.default(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .overlayGlassBackground(in: Circle())
            .clipShape(Circle())
            .accessibilityLabel("Back to attach menu")
            .accessibilityIdentifier("attach-photos-back")

            Spacer()

            // One or the other, cross-faded in place as the first pick arrives and the last leaves.
            if pick.selection.isEmpty {
                Button {
                    if let onAllPhotos {
                        onAllPhotos()
                    } else {
                        pick.showsLibrary = true
                    }
                } label: {
                    Text("All Photos")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .overlayGlassBackground(in: Capsule())
                .clipShape(Capsule())
                .accessibilityIdentifier("attach-photos-all")
                .transition(.opacity)
            } else {
                Button {
                    pick.handOff(to: onAdd)
                } label: {
                    Text(Self.addTitle(count: pick.selection.count))
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textAction)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(Color.action, in: Capsule())
                        .contentShape(Capsule())
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("attach-photos-add")
                .transition(.opacity)
            }
        }
        .padding(12)
        .animation(ChatMotion.composerChip.animation, value: pick.selection.isEmpty)
        .animation(ChatMotion.composerChip.animation, value: pick.selection.count)
    }
}
