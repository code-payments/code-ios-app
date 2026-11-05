//
//  ChatPhotoSendProgress.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

/// How far one outgoing photo has got, from encoding through the message that carries it.
///
/// One per staged photo, so each bubble in a multi-photo send draws its own progress.
@MainActor
@Observable
public final class ChatPhotoSendProgress {

    public enum Phase: Equatable, Sendable {
        /// Encoding, encrypting, or reserving the upload; no bytes have gone out yet.
        case preparing
        /// Sending bytes to storage, with the share of them sent.
        case uploading(fraction: Double)
        /// Stored, while the server checks the bytes before they can be served.
        case processing
        /// Posting the message that references the stored photo.
        case sending
        /// The message is confirmed.
        case sent
        /// The upload or the message failed; the transcript's retry affordance takes over.
        case failed
    }

    public private(set) var phase: Phase = .preparing

    public init() {}

    /// Whether the bubble draws a progress overlay for this phase.
    public var showsOverlay: Bool {
        switch phase {
        case .preparing, .uploading, .processing, .sending:
            true
        case .sent, .failed:
            false
        }
    }

    /// One phase for photos sent together, which a stack's front draws for the whole send: nil
    /// counts as a photo already confirmed, and a failed one is left out. Preparing until any has
    /// bytes going out, then the share of the send uploaded, with each photo past its upload
    /// counting as done, then the slowest of the rest. Nil when none has progress.
    public static func combined(_ phases: [Phase?]) -> Phase? {
        guard phases.contains(where: { $0 != nil }) else { return nil }
        let live = phases.map { $0 ?? .sent }.filter { $0 != .failed }
        guard !live.isEmpty else { return .failed }
        if live.allSatisfy({ $0 == .preparing }) { return .preparing }
        func uploaded(_ phase: Phase) -> Double? {
            switch phase {
            case .preparing:                  0
            case .uploading(let fraction):    fraction
            case .processing, .sending, .sent: nil
            case .failed:                     nil
            }
        }
        if live.contains(where: { uploaded($0) != nil }) {
            let total = live.reduce(0) { $0 + (uploaded($1) ?? 1) }
            return .uploading(fraction: total / Double(live.count))
        }
        if live.contains(.processing) { return .processing }
        if live.contains(.sending) { return .sending }
        return .sent
    }

    /// Starts an upload attempt over, including after a failure or a retried store.
    public func beginAttempt() {
        phase = .preparing
    }

    /// Records bytes sent to storage.
    ///
    /// Byte counts arrive asynchronously from the network, so one landing after the upload has
    /// moved on is ignored, and the bar never runs backwards within an attempt.
    public func didUpload(_ progress: BlobUploadProgress) {
        guard let fraction = progress.fraction else { return }
        switch phase {
        case .preparing:
            phase = .uploading(fraction: fraction)
        case .uploading(let current):
            if fraction > current { phase = .uploading(fraction: fraction) }
        case .processing, .sending, .sent, .failed:
            break
        }
    }

    /// Records that the bytes are stored and the server is finalizing them.
    public func beginProcessing() {
        phase = .processing
    }

    /// Records that the message referencing the photo is being posted.
    public func beginSending() {
        phase = .sending
    }

    /// Records that the message is confirmed.
    public func finish() {
        phase = .sent
    }

    /// Records that the upload or the message failed.
    public func fail() {
        phase = .failed
    }
}

extension ChatPhotoSendProgress: ChatPhotoUploadProgress {}
