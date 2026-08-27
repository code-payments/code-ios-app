//
//  ChatReceipt.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The status line under the user's latest sent bubble.
///
/// A case rather than a string, because the view animates *between* states: Delivered giving way to
/// Read is a cross-fade of two labels, not a text assignment, and it can only tell those apart if
/// the difference survives the mapping layer. The copy is still produced in one place — this type
/// holds it — so the cell renders and never decides.
///
/// `status` and `time` are separate because they are set in different weights.
public enum ChatReceipt: Hashable, Sendable, Codable {

    /// The server has the message; the counterpart hasn't read it.
    case delivered
    /// The counterpart's read pointer has reached the message. `time` is the formatted moment they
    /// read it ("3:42 PM", "Yesterday", "Tue, Jun 17"), or nil when the server omits the timestamp.
    case read(time: String?)
    /// The send failed. Carries its own copy because the line doubles as the retry affordance.
    case failed(String)

    /// The leading, bolder half of the line.
    public var status: String {
        switch self {
        case .delivered:          "Delivered"
        case .read:               "Read"
        case .failed(let text):   text
        }
    }

    /// The trailing, lighter half, or nil when the line is status only.
    public var time: String? {
        switch self {
        case .delivered:  nil
        case .read(let time): time
        case .failed:     nil
        }
    }

    /// The whole line as one string, for accessibility and for tests.
    public var displayText: String {
        guard let time else { return status }
        return "\(status) \(time)"
    }

    /// Whether this line reports a failure: the cell turns it red and makes the row tappable.
    public var isFailed: Bool {
        switch self {
        case .delivered, .read: false
        case .failed:           true
        }
    }
}
