//
//  NotificationTranscriptView.swift
//  NotificationContent
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A lightweight SwiftUI transcript for the notification content extension: a bottom-anchored,
/// scrollable list of chat bubbles. It deliberately avoids the in-app `ChatViewController`
/// (UICollectionView + custom `ChatLayout`), whose footprint exceeds a content extension's memory
/// budget and gets the extension jetsam-killed. It renders the same `[ChatItem]` the in-app chat
/// does and matches its bubble chrome.
struct NotificationTranscriptView: View {

    let items: [ChatItem]

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    // The in-app chat uses 4pt rows, but it also renders receipts and groups
                    // same-sender bubbles for separation; the preview does neither, so it needs a
                    // larger gap to read comfortably.
                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            switch item {
                            case .message(let message):
                                NotificationMessageRow(message: message)
                                    .transition(.opacity)
                            case .dateSeparator(_, let text):
                                NotificationDateSeparator(text: text)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // Pin the transcript to the bottom so the newest message sits at the panel's
                    // bottom edge, with empty space filling above when it's shorter than the panel.
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                    .padding(.horizontal, 12)
                    // Fade new messages in / old ones out as the transcript refreshes — opacity
                    // only, so it doesn't fight the scroll-to-newest snap or the bottom anchoring.
                    .animation(.easeInOut(duration: 0.2), value: items)
                }
                .defaultScrollAnchor(.bottom)
                // `.defaultScrollAnchor` sets the anchor on the empty first render and doesn't
                // re-anchor when the transcript loads afterward, so scroll to the newest message
                // explicitly once it arrives (and on each refresh).
                .onChange(of: items, initial: true) {
                    guard let newest = items.last?.id else { return }
                    proxy.scrollTo(newest, anchor: .bottom)
                }
            }
        }
    }
}

/// Aligns a message to its sender's side — `.me` trailing, `.other` leading — and renders the
/// bubble for its content.
private struct NotificationMessageRow: View {

    let message: ChatMessage

    var body: some View {
        HStack(spacing: 0) {
            if message.sender == .me { Spacer(minLength: 44) }
            switch message.content {
            case .text(let text):
                NotificationTextBubble(text: text, isFromSelf: message.sender == .me)
            case .cash(let cash):
                NotificationCashCard(cash: cash, isFromSelf: message.sender == .me)
            }
            if message.sender == .other { Spacer(minLength: 44) }
        }
    }
}

/// A centered "Today 12:13 PM"-style date header, matching the in-app chat's separator.
private struct NotificationDateSeparator: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.default(size: 12, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity)
    }
}

/// A text bubble matching the in-app chat: 16pt medium white text, a white-opacity fill split by
/// sender, a hairline border, and continuous 12pt corners.
private struct NotificationTextBubble: View {

    let text: String
    let isFromSelf: Bool

    var body: some View {
        Text(text)
            .font(.appTextMessage)
            .foregroundStyle(Color.textMain)
            .frame(maxWidth: 256, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFromSelf ? 0.08 : 0.02))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
    }
}

/// A payment "cash card" matching `ChatCashCardCell` (232×170): a token row top-left, a centered
/// "You sent / You received" caption over the currency flag + amount, and the same bubble chrome.
private struct NotificationCashCard: View {

    let cash: ChatCashContent
    let isFromSelf: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape
            .fill(Color.white.opacity(isFromSelf ? 0.08 : 0.02))
            .background(Color.backgroundMain, in: shape)
            .frame(width: 232, height: 170)
            .overlay(alignment: .topLeading) {
                NotificationCashTokenRow(token: cash.token, iconURL: cash.iconURL)
            }
            .overlay {
                NotificationCashCenter(
                    caption: isFromSelf ? "You sent" : "You received",
                    amount: cash.amount,
                    flagImageName: cash.flagImageName
                )
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.03), lineWidth: 1)
            }
    }
}

/// The card's top-left token row: the mint's coin icon (when resolved) + token name.
private struct NotificationCashTokenRow: View {

    let token: String
    let iconURL: URL?

    var body: some View {
        HStack(spacing: 4) {
            if let iconURL {
                NotificationCoinIcon(url: iconURL)
            }
            Text(token)
                .font(.default(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.leading, 11)
        .padding(.top, 8)
    }
}

/// The card's centered caption over the currency flag + amount.
private struct NotificationCashCenter: View {

    let caption: String
    let amount: String
    let flagImageName: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(caption)
                .font(.default(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
            HStack(spacing: 11) {
                if let flagImageName, let flag = Image.cashFlag(named: flagImageName) {
                    flag
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                }
                Text(amount)
                    .font(.default(size: 38, weight: .bold))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Asynchronously loads a circular 13pt coin icon for a launchpad token, mirroring
/// `ChatCashCardCell`'s lightweight `URLSession` fetch.
private struct NotificationCoinIcon: View {

    let url: URL

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Color.white.opacity(0.15)
            }
        }
        .frame(width: 13, height: 13)
        .clipShape(Circle())
        .task(id: url) {
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let uiImage = UIImage(data: data) else { return }
            image = Image(uiImage: uiImage)
        }
    }
}
