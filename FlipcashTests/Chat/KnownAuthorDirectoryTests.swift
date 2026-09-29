//
//  KnownAuthorDirectoryTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

/// Naming a group's senders when the chat's own roster cannot: what the directory fetches, what it
/// caches, and what it refuses to ask for twice.
@MainActor
@Suite("KnownAuthorDirectory profile resolution")
struct KnownAuthorDirectoryTests {

    /// The fake store behind the directory. Lock-guarded rather than actor-isolated because the
    /// directory reads and writes it from a detached task, the way the real `Database` is used.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var state = State()

        struct State {
            var table: [UserID: ConversationMember] = [:]
            var requests: [UserID] = []
            var cached: [UserID: Profile] = [:]
            var failing: Set<UserID> = []
            var nameless: Set<UserID> = []
        }

        func withState<Value>(_ body: (inout State) -> Value) -> Value {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }

        var requests: [UserID] { withState { $0.requests } }
        var cached: [UserID: Profile] { withState { $0.cached } }
    }

    private enum Unreachable: Error { case offline }

    private func directory(_ recorder: Recorder) -> KnownAuthorDirectory {
        KnownAuthorDirectory(
            read: { recorder.withState { $0.table } },
            fetch: { userID in
                let (fails, isNameless) = recorder.withState { state in
                    state.requests.append(userID)
                    return (state.failing.contains(userID), state.nameless.contains(userID))
                }
                if fails { throw Unreachable.offline }
                if isNameless {
                    return try Profile(displayName: nil, phone: String?.none, email: nil, userID: userID, username: Username("ada"))
                }
                return try Profile(displayName: "Ada", phone: String?.none, email: nil, userID: userID)
            },
            cache: { profile, userID in
                recorder.withState { state in
                    state.cached[userID] = profile
                    state.table[userID] = ConversationMember(
                        userID: userID,
                        displayName: profile.displayName ?? ""
                    )
                }
            }
        )
    }

    @Test("A sender the local cache cannot name is fetched, cached and landed in the snapshot")
    func fetchesAndCachesAnUnknownSender() async {
        let recorder = Recorder()
        let sender = UserID()
        let directory = directory(recorder)

        await directory.resolve([sender])

        #expect(recorder.requests == [sender])
        #expect(recorder.cached[sender]?.displayName == "Ada")
        #expect(directory.snapshot.membersByUserID[sender]?.displayName == "Ada")
    }

    @Test("A sender the local cache already names costs no round trip")
    func skipsSendersTheCacheAlreadyNames() async {
        let recorder = Recorder()
        let sender = UserID()
        recorder.withState { $0.table[sender] = ConversationMember(userID: sender, displayName: "Grace") }
        let directory = directory(recorder)
        await directory.reload()

        await directory.resolve([sender])

        #expect(recorder.requests.isEmpty)
    }

    @Test("A sender is asked about once, however often the transcript re-maps")
    func asksOncePerSender() async {
        let recorder = Recorder()
        let sender = UserID()
        let directory = directory(recorder)

        await directory.resolve([sender])
        await directory.resolve([sender])

        #expect(recorder.requests == [sender])
    }

    @Test("A failed fetch is retried, so a sender is not lost to one bad request")
    func retriesAfterAFailure() async {
        let recorder = Recorder()
        let sender = UserID()
        recorder.withState { $0.failing = [sender] }
        let directory = directory(recorder)

        await directory.resolve([sender])
        #expect(directory.snapshot.membersByUserID[sender] == nil)

        recorder.withState { $0.failing = [] }
        await directory.resolve([sender])

        #expect(recorder.requests == [sender, sender])
        #expect(directory.snapshot.membersByUserID[sender]?.displayName == "Ada")
    }

    @Test("A resolved sender invalidates the snapshot, so a Chats row reading it redraws")
    func resolveInvalidatesSnapshotObservers() async {
        let recorder = Recorder()
        let sender = UserID()
        let directory = directory(recorder)

        await confirmation("snapshot invalidated") { invalidated in
            withObservationTracking {
                _ = directory.snapshot
            } onChange: {
                invalidated()
            }
            await directory.resolve([sender])
        }
    }

    @Test("A nameless sender is attributed for this launch, without being cached or asked again")
    func resolve_namelessSender_heldForLaunchNotCached() async {
        let recorder = Recorder()
        let sender = UserID()
        recorder.withState { $0.nameless = [sender] }
        let directory = directory(recorder)

        await directory.resolve([sender])
        await directory.resolve([sender])

        #expect(recorder.requests == [sender])
        #expect(recorder.cached[sender] == nil)
        let member = directory.snapshot.membersByUserID[sender]
        #expect(member?.displayName == "")
        #expect(member?.username == Username("ada"))
    }
}
