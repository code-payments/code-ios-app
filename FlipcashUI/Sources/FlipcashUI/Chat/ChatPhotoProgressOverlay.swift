//
//  ChatPhotoProgressOverlay.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import Observation

/// A thin bar in the corner of an outgoing photo, after iMessage's send bar, that follows its
/// ``ChatPhotoSendProgress``.
///
/// The bar fills with the bytes sent. Once they are stored, the server's processing and the message
/// send have no measurable progress, so a blue segment slides along the track instead — held still
/// in the middle under Reduce Motion. The bar fades out when the message is sent, and is gone at once on a failure,
/// where the row's failed receipt and tap-to-retry take over.
final class ChatPhotoProgressOverlay: UIView {

    static let size = CGSize(width: 64, height: 5)
    private static let fadeDuration: TimeInterval = 0.25
    private static let fillDuration: TimeInterval = 0.2
    private static let segmentShare: CGFloat = 0.35
    private static let slideDuration: CFTimeInterval = 1.1
    private static let slideKey = "slide"

    private let track = UIView()
    private let fill = UIView()
    private let segment = UIView()

    private var progress: ChatPhotoSendProgress?
    /// Set while the row is failed, which hides the bar whatever the progress says.
    private var suppressed = false
    /// Bumped on every bind, so an observation armed for an earlier row is dropped.
    private var generation = 0

    /// The share of the bar drawn filled.
    private(set) var fraction: CGFloat = 0
    /// Whether the bar is showing, or fading in to show.
    private(set) var isShowing = false
    /// Whether the bar is in its indeterminate, post-upload state.
    private(set) var isIndeterminate = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        alpha = 0
        isHidden = true

        // The shadow keeps the bar legible over a white region of the photo.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 2
        layer.shadowOffset = .zero

        track.backgroundColor = UIColor(Color.backgroundMain).withAlphaComponent(0.35)
        track.layer.cornerRadius = Self.size.height / 2
        track.clipsToBounds = true
        addSubview(track)

        fill.backgroundColor = .systemBlue
        track.addSubview(fill)

        segment.backgroundColor = .systemBlue
        segment.layer.cornerRadius = Self.size.height / 2
        segment.isHidden = true
        track.addSubview(segment)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { Self.size }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        fill.frame = CGRect(x: 0, y: 0, width: track.bounds.width * fraction, height: track.bounds.height)
        let width = track.bounds.width * Self.segmentShare
        segment.bounds = CGRect(x: 0, y: 0, width: width, height: track.bounds.height)
        segment.center = CGPoint(x: track.bounds.midX, y: track.bounds.midY)
        // A slide armed before the track had a width never started.
        if isIndeterminate, segment.layer.animation(forKey: Self.slideKey) == nil { startSliding() }
    }

    /// Follows `progress`, or shows nothing when it is nil. `animated` is false for a row the
    /// overlay was not already drawing, so a recycled cell never fades another row's state.
    func bind(_ progress: ChatPhotoSendProgress?, suppressed: Bool, animated: Bool) {
        generation += 1
        self.progress = progress
        self.suppressed = suppressed
        render(animated: animated)
        observe(generation: generation)
    }

    private func observe(generation armed: Int) {
        guard let progress else { return }
        withObservationTracking {
            _ = progress.phase
        } onChange: { [weak self] in
            // Fires before the new value is readable; render once it has landed.
            Task { @MainActor [weak self] in
                guard let self, self.generation == armed else { return }
                self.render(animated: true)
                self.observe(generation: armed)
            }
        }
    }

    private func render(animated: Bool) {
        let phase = suppressed ? nil : progress?.phase
        let animated = animated && window != nil

        let target: (show: Bool, fraction: CGFloat, indeterminate: Bool)
        switch phase {
        case .preparing:
            target = (true, 0, false)
        case .uploading(let value):
            target = (true, CGFloat(value), false)
        case .processing, .sending:
            target = (true, 1, true)
        case .sent:
            target = (false, 1, false)
        case .failed, nil:
            target = (false, fraction, false)
        }

        if target.show {
            setFraction(target.fraction, animated: animated)
            setIndeterminate(target.indeterminate)
        }
        // A failure hands straight to the failed receipt. Anything else leaving fades: a send, or a
        // row whose progress went away because its send confirmed.
        setShowing(target.show, animated: animated && !suppressed && phase != .failed)
    }

    private func setFraction(_ value: CGFloat, animated: Bool) {
        guard value != fraction else { return }
        fraction = value
        guard animated, !UIAccessibility.isReduceMotionEnabled, !isHidden else {
            setNeedsLayout()
            return
        }
        UIView.animate(withDuration: Self.fillDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.layoutIfNeeded()
        }
        setNeedsLayout()
    }

    private func setIndeterminate(_ indeterminate: Bool) {
        guard indeterminate != isIndeterminate else { return }
        isIndeterminate = indeterminate
        fill.isHidden = indeterminate
        segment.isHidden = !indeterminate
        if indeterminate { startSliding() } else { stopSliding() }
    }

    private func startSliding() {
        guard !UIAccessibility.isReduceMotionEnabled, track.bounds.width > 0 else { return }
        let half = segment.bounds.width / 2
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = -half
        slide.toValue = track.bounds.width + half
        slide.duration = Self.slideDuration
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        slide.repeatCount = .infinity
        slide.isRemovedOnCompletion = false
        segment.layer.add(slide, forKey: Self.slideKey)
    }

    private func stopSliding() {
        segment.layer.removeAnimation(forKey: Self.slideKey)
    }

    private func setShowing(_ show: Bool, animated: Bool) {
        guard show != isShowing else { return }
        isShowing = show
        if show {
            isHidden = false
            layoutIfNeeded()
        }
        let apply = { self.alpha = show ? 1 : 0 }
        guard animated else {
            apply()
            isHidden = !show
            if !show { setIndeterminate(false) }
            return
        }
        UIView.animate(withDuration: Self.fadeDuration, delay: 0, options: [.beginFromCurrentState], animations: apply) { _ in
            guard !self.isShowing else { return }
            self.isHidden = true
            self.setIndeterminate(false)
        }
    }
}
#endif
