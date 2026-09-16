//
//  GatePreviewPlaceholder.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

/// The shapes drawn behind the gate's blur for a chat the signed-in user has not joined (node
/// 10127:117171).
///
/// Decorative, and deliberately so. The contract has no read for a non-member — `GetMessages` is
/// denied to anyone outside the roster — so there is nothing real to blur, and the design's soft
/// bubbles behind the gate panel are set dressing rather than a preview of the conversation. These
/// are fixed shapes: no message, no author and no timestamp is ever fetched to make them.
final class GatePreviewPlaceholder {

    /// Matches `TranscriptBlur`'s fade, so the shapes and the blur that softens them arrive
    /// together rather than one under the other.
    private static let duration: TimeInterval = 0.25

    /// Each row as the design lays it out: the bubble's width as a fraction of the transcript's,
    /// its height, and which side it hangs off.
    private static let rows: [(width: CGFloat, height: CGFloat, isOutgoing: Bool)] = [
        (0.62, 40, false),
        (0.45, 40, true),
        (0.74, 62, false),
        (0.38, 40, true),
        (0.56, 40, false),
        (0.66, 62, true),
        (0.42, 40, false),
    ]

    private static let horizontalInset: CGFloat = 16
    private static let rowSpacing: CGFloat = 8
    private static let radius: CGFloat = 18

    private let container = UIView()

    /// Whether the shapes are drawn. Setting it to the value it already has is a no-op, so a
    /// re-render reporting the same gate doesn't restart the fade.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            UIView.animate(withDuration: Self.duration) {
                self.container.alpha = self.isShown ? 1 : 0
            }
        }
    }

    /// Adds the shapes to `host`, pinned to its edges and layered directly under `sibling` — the
    /// blur, which is the only reason they are legible as chat at all. Called once, while the
    /// screen is being built; the shapes start hidden.
    func install(in host: UIView, below sibling: UIView) {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alpha = 0
        // Purely decorative, so it never takes a touch that the transcript or the gate panel
        // behind it would have handled.
        container.isUserInteractionEnabled = false
        host.insertSubview(container, belowSubview: sibling)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: host.topAnchor),
            container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        let fill = UIColor(Color.white.opacity(0.08))
        var previous: UIView?
        for row in Self.rows {
            let bubble = UIView()
            bubble.translatesAutoresizingMaskIntoConstraints = false
            bubble.backgroundColor = fill
            bubble.layer.cornerRadius = Self.radius
            bubble.layer.cornerCurve = .continuous
            container.addSubview(bubble)

            NSLayoutConstraint.activate([
                bubble.heightAnchor.constraint(equalToConstant: row.height),
                bubble.widthAnchor.constraint(
                    equalTo: container.widthAnchor,
                    multiplier: row.width,
                    constant: -Self.horizontalInset
                ),
                row.isOutgoing
                    ? bubble.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.horizontalInset)
                    : bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.horizontalInset),
                bubble.topAnchor.constraint(
                    equalTo: previous?.bottomAnchor ?? container.safeAreaLayoutGuide.topAnchor,
                    constant: Self.rowSpacing
                ),
            ])
            previous = bubble
        }
    }
}
#endif
