//
//  SharedImageScanInbox.swift
//  Flipcash
//

import SwiftUI

/// The app-side flag that a shared image is waiting in the group container.
///
/// `DeepLinkController` raises it when the share extension's handoff URL arrives; `HomeTabView`
/// brings the Scan tab forward on it and `ScanScreen` lowers it as it scans. Separate from the
/// image itself, which stays in ``SharedImageInbox`` until the scan takes it — so an app killed
/// between the two still finds the image on the next Scan-tab visit.
///
/// Lives on `SessionContainer` for the same reason `OnrampDeeplinkInbox` does: it must outlive
/// the screens that read it, but not the session.
@Observable
@MainActor
final class SharedImageScanInbox {
    var hasPendingImage = false
}
