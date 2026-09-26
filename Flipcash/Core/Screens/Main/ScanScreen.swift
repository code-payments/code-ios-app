//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-07.
//

import PhotosUI
import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thin environment-reading wrapper that hands the DI containers to
/// ``ScanScreenContent``, whose `init` builds the `@State` scan view model and
/// `@Bindable` session synchronously. Mounted as the Scan tab of
/// ``HomeTabView``, which owns the app-level `router.rootSheet` host.
struct ScanScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        ScanScreenContent(container: container, sessionContainer: sessionContainer)
    }
}

private struct ScanScreenContent: View {

    @Environment(Preferences.self) private var preferences

    @Bindable private var session: Session

    @State private var viewModel: ScanViewModel

    @State private var cameraAuthorizer = CameraAuthorizer()

    @State private var pickedItem: PhotosPickerItem?
    @State private var isScanningStillImage = false
    @State private var scanTask: Task<ScanViewModel.StillImageOutcome, Never>?

    private var cameraPrompt: CameraPrompt? {
        CameraPrompt(status: cameraAuthorizer.status, cameraEnabled: preferences.cameraEnabled)
    }
    
    /// How far the gallery button sits in from the trailing edge — the same margin
    /// the rest of the app's content uses.
    private static let glyphTrailingMargin: CGFloat = 20

    /// The gap between the top safe area and the gallery button. Measured from the
    /// inset rather than the screen edge: the camera preview ignores the safe area
    /// and runs under the status bar, but the button must stay clear of it.
    private static let glyphTopGap: CGFloat = 12

    private let sessionContainer: SessionContainer

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session

        self.viewModel = ScanViewModel(
            container: container,
            sessionContainer: sessionContainer
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        let showControls = session.billState.bill == nil
        ZStack {
            if cameraPrompt == nil {
                cameraViewport()
                    .transition(.identity)
            }
            
            if showControls {
                // Any actionable views need to be positioned
                // in front of the BillCanvas, otherwise it
                // will swallow all touch events
                if let cameraPrompt {
                    CameraPromptView(prompt: cameraPrompt, embedded: true) {
                        performCameraPromptAction(cameraPrompt)
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }

                // Outside the `cameraPrompt` branch on purpose: a photo can be scanned
                // whether or not the camera is available, so the glyph outlives the viewport.
                GalleryScanButton(selection: $pickedItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, Self.glyphTrailingMargin)
                    .padding(.top, Self.glyphTopGap)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        // Fill the tab's full width and height. The iOS 26 native `TabView` does
        // not stretch tab content to fill, so without this the ZStack collapses to
        // its content width (the centered `CameraPromptView` at ~340pt, or the
        // camera viewport), leaving black bars down both sides of the scanner.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
        .animation(.easeInOut(duration: 0.15), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: preferences.cameraEnabled)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await scanPickedItem(item) }
        }
        // Watched rather than read on appear, so an image shared while the Scan tab is already
        // forward scans without the user leaving and coming back; `initial: true` catches the
        // cold start, where the link is handled before this view exists.
        //
        // Deliberately not `.task(id:)`: clearing the flag would change the id and cancel the
        // scan it just started. An unstructured `Task`, as the picked-item path above uses,
        // outlives the view update that clearing it causes.
        .onChange(of: sessionContainer.sharedImageScanInbox.hasPendingImage, initial: true) { _, isPending in
            guard isPending else { return }
            sessionContainer.sharedImageScanInbox.hasPendingImage = false

            Task { await scanSharedImage() }
        }
        .overlay {
            if isScanningStillImage {
                ScanningOverlay {
                    scanTask?.cancel()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isScanningStillImage)
        .ignoresSafeArea(.keyboard)
        // Tells the app-root bill overlay the camera is behind it, so a grabbed
        // bill shows over the live camera without a scrim while the Scan tab is
        // forward. Any other surface gets the scrim.
        .onAppear { session.isScannerForeground = true }
        .onDisappear { session.isScannerForeground = false }
    }

    @ViewBuilder private func cameraViewport() -> some View {
        CameraViewport(
            session: viewModel.cameraSession,
            enableGestures: true
        )
        // Cross-fade the live preview in only once the first frame arrives, over
        // the dark placeholder — so the camera warm-up after a tab switch never
        // shows a black frame. See `ScanViewModel.isPreviewReady`.
        .opacity(viewModel.isPreviewReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPreviewReady)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configureCameraSession()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
    
    /// Loads the picked image and scans it.
    ///
    /// The overlay goes up before the load rather than inside ``scan(_:)``: `loadTransferable`
    /// on a full-resolution photo takes long enough that the tap would otherwise look like it
    /// did nothing.
    private func scanPickedItem(_ item: PhotosPickerItem) async {
        isScanningStillImage = true
        defer { pickedItem = nil }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)?.cgImage
        else {
            isScanningStillImage = false
            session.dialogItem = .noCodeFound
            return
        }

        await scan(image)
    }

    /// Scans an image shared to the app through the share extension.
    ///
    /// Takes the handover, which empties it — see ``SharedImageInbox``. An empty inbox or bytes
    /// that do not decode report nothing: the user is looking at the live scanner either way,
    /// and a dialog about an image the app never showed them would explain nothing.
    private func scanSharedImage() async {
        guard
            let inbox = SharedImageInbox(),
            let data = try? inbox.take(),
            let image = UIImage(data: data)?.cgImage
        else {
            return
        }

        await scan(image)
    }

    /// Runs the still-image ladder and reports the outcome through the app's dialog.
    ///
    /// The overlay is blocking for the length of the search, so the idle timer goes with it:
    /// there is nothing to touch while the ladder runs, and the screen dimming mid-search
    /// would read as the app having stalled.
    private func scan(_ image: CGImage) async {
        isScanningStillImage = true
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isScanningStillImage = false
            scanTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }

        let task = Task { await viewModel.scanStillImage(image) }
        scanTask = task

        switch await task.value {
        case .handled:
            break
        case .nothingFound:
            session.dialogItem = .noCodeFound
        case .cashCodeNotLive:
            session.dialogItem = .cashCodeNotLive
        }
    }

    private func performCameraPromptAction(_ prompt: CameraPrompt) {
        switch prompt {
        case .requestPermission:
            Task {
                try await cameraAuthorizer.authorize()
            }
        case .openSettings:
            URL.openSettings()
        case .startCamera:
            preferences.cameraEnabled.toggle()
        }
    }

}

/// A blocking, cancellable overlay for the duration of a still-image search.
///
/// Blocking on purpose: the search can take seconds, and a half-scanned photo is not a
/// state worth showing. Cancellable for the same reason.
private struct ScanningOverlay: View {

    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)

                Text("Looking for a code\u{2026}")
                    .foregroundStyle(.white)

                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Dialogs -

private extension DialogItem {

    /// Also what a refused route reports. Someone who has been sent a login QR learns
    /// nothing from this about why it was refused, which is the point.
    static var noCodeFound: DialogItem {
        .info(
            title: "No Code Found",
            subtitle: "We couldn't find a code in that photo."
        )
    }

    static var cashCodeNotLive: DialogItem {
        .info(
            title: "Cash Code Isn't Live",
            subtitle: "That cash code isn't live any more. Ask them to show it on their screen while you scan."
        )
    }
}
