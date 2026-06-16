//
//  ConversationController+DebugBlast.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if DEBUG
import Foundation
import FlipcashCore

private let logger = Logger(label: "flipcash.conversation-debug-blast")

extension ConversationController {

    /// Sends `count` varied text messages into `conversationID` through the real
    /// send path, one at a time, for on-device transcript performance testing.
    ///
    /// Sequential by design: each `send` merges one server-assigned message into
    /// the store, so every arrival is a single observation update paced by the
    /// round-trip — not a burst of concurrent merges that would thrash the
    /// transcript's view updates.
    func blastMessages(count: Int, into conversationID: ConversationID) async {
        logger.info("Starting debug message blast", metadata: [
            "count": "\(count)",
            "conversationID": "\(conversationID)",
        ])

        var sent = 0
        for _ in 0..<count {
            let text = Self.debugBlastCorpus.randomElement() ?? "Hello"
            if await send(text, to: conversationID) {
                sent += 1
            }
        }

        logger.info("Finished debug message blast", metadata: [
            "sent": "\(sent)",
            "requested": "\(count)",
        ])
    }

    /// A spread of lengths, emoji density, and line counts so the blast exercises
    /// bubble width, wrapping, and grouping rather than one uniform shape.
    private static let debugBlastCorpus: [String] = [
        "ok",
        "lol",
        "👍",
        "😂😂😂",
        "🔥",
        "yes!!",
        "nope",
        "brb",
        "👀",
        "wait what 😳",
        "haha no way 😂",
        "omg 🥹 that's amazing",
        "gm ☀️",
        "🎉🎉🎉🥳",
        "❤️❤️❤️",
        "🚀🚀🚀 to the moon",
        "🍕🍔🌮 lunch?",
        "see you soon!",
        "Sounds good, let's do it 👍",
        "Can you send me the address again?",
        "Thanks so much, really appreciate it 🙏",
        "Let me check and get back to you",
        "Running about 10 minutes late, traffic is brutal 🚗💨",
        "Did you see the game last night? Absolutely wild finish.",
        "So here's the plan: we meet around 7, grab a quick bite, then head over. Should be done by 11 or so — let me know if that works for you!",
        "I was thinking about what you said earlier and you're totally right. We should rethink the whole approach before we commit. Let's talk tomorrow.",
        "Top of the list:\n• milk\n• eggs\n• coffee\n• something for dinner",
        "💸💸💸",
        "on my way 🚗💨",
        "perfect, thank you!",
    ]
}
#endif
