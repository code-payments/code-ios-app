//
//  RosterSync.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.roster-sync")

/// Keeps the full roster of each group the user opens on device, for member search.
///
/// A group is tracked from its first open. The first open reads `Chat.GetRoster` to the end. Later
/// opens catch up only when the roster moved past the last version a read applied: they re-read
/// from the first page, newest joins first, and stop at a member already covered. ``apply(_:)``
/// keeps a tracked group current from the stream in between. Groups never opened are not fetched.
/// Every path merges per member by roster version, greater winning.
actor RosterSync {

    /// Pages a read fetches before it stops, `has_more` or not; at 100 per page, 2,000 members.
    static let defaultPageCap = 20

    private let fetching: any RosterFetching
    private let database: Database
    private let owner: KeyPair
    private let pageCap: Int

    /// Reads in flight, so a second trigger for the same group joins the first rather than reading twice.
    private var inFlight: [ConversationID: Task<Void, Never>] = [:]

    init(fetching: any RosterFetching, database: Database, owner: KeyPair, pageCap: Int = RosterSync.defaultPageCap) {
        self.fetching = fetching
        self.database = database
        self.owner = owner
        self.pageCap = pageCap
    }

    /// Starts tracking a group and brings its held roster up to date: a full read when none has
    /// finished or a reconcile is owed, a catch-up when the roster moved past the watermark, nothing
    /// otherwise. Returns once any read is done.
    func syncIfNeeded(_ conversationID: ConversationID) async {
        await run(conversationID, refreshFirstPage: false)
    }

    /// As ``syncIfNeeded(_:)``, but always re-reads at least the first page, so the newest members'
    /// names and pictures are current; profile changes don't move the roster version.
    func refreshFirstPage(_ conversationID: ConversationID) async {
        await run(conversationID, refreshFirstPage: true)
    }

    /// Writes a stream roster update into the held roster of a tracked group; other events are ignored.
    @MainActor
    func apply(_ event: ConversationStreamEvent) {
        guard case .rosterChanged(let conversationID, let updates) = event else { return }
        do {
            try database.applyRosterUpdates(updates, conversationID: conversationID)
        } catch {
            logger.error("Failed to apply roster updates", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to apply roster updates")
        }
    }

    // MARK: - Private -

    private func run(_ conversationID: ConversationID, refreshFirstPage: Bool) async {
        if let running = inFlight[conversationID] {
            await running.value
            return
        }
        let task = Task { await self.bringUpToDate(conversationID, refreshFirstPage: refreshFirstPage) }
        inFlight[conversationID] = task
        await task.value
        inFlight[conversationID] = nil
    }

    private func bringUpToDate(_ conversationID: ConversationID, refreshFirstPage: Bool) async {
        let state: RosterSyncState
        do {
            try database.beginTrackingRoster(conversationID: conversationID)
            guard let tracked = try database.rosterSyncState(conversationID: conversationID) else { return }
            state = tracked
        } catch {
            await report(error, reason: "Failed to read roster sync state", conversationID: conversationID)
            return
        }

        if state.needsFullRead {
            await fullRead(conversationID, reconciling: state.reconcilePending)
            return
        }
        guard state.needsCatchUp || refreshFirstPage else { return }

        do {
            switch try await catchUp(conversationID, watermark: state.watermark) {
            case .caughtUp:
                break
            case .reconcileNeeded:
                await fullRead(conversationID, reconciling: true)
            }
        } catch {
            await report(error, reason: "Failed to catch up roster", conversationID: conversationID)
        }
    }

    /// Reads from the first page until it reaches a member the watermark already covers.
    private func catchUp(_ conversationID: ConversationID, watermark: UInt64) async throws -> RosterCatchUpOutcome {
        // Pages list the most recently joined first, and a member's version is the roster version of
        // their join, so everyone after the first member at or below the watermark is already held.
        // `Member.version` is documented to move on future member changes too (a role change, say);
        // once one does, a member can sit above the watermark out of join order, and this stop rule
        // needs revisiting.
        let read = try await readPages(conversationID) { page in
            page.members.contains { $0.version <= watermark }
        }

        guard read.stoppedEarly else {
            // The read ran to the end or the cap without reaching the watermark: it's a full read.
            try database.applyFullRosterRead(read.members, summaries: read.summaries, isComplete: read.reachedEnd, conversationID: conversationID)
            logRead("Roster catch-up became a full read", read, conversationID: conversationID)
            return .caughtUp
        }

        guard let summary = read.summaries.min(by: { $0.version < $1.version }) else { return .caughtUp }
        let outcome = try database.applyRosterCatchUp(read.members, summary: summary, conversationID: conversationID)
        logRead("Caught up roster", read, conversationID: conversationID)
        return outcome
    }

    /// Reads the whole roster, up to the page cap. A reconcile runs at background priority, since it
    /// only removes members who left; a failure leaves it pending for the next open.
    private func fullRead(_ conversationID: ConversationID, reconciling: Bool) async {
        let task = Task(priority: reconciling ? .background : nil) {
            let read = try await self.readPages(conversationID) { _ in false }
            try self.database.applyFullRosterRead(read.members, summaries: read.summaries, isComplete: read.reachedEnd, conversationID: conversationID)
            await self.logRead("Read full roster", read, conversationID: conversationID)
        }
        do {
            try await task.value
        } catch {
            await report(error, reason: "Failed to read full roster", conversationID: conversationID)
        }
    }

    private struct Read {
        var members: [ConversationMember] = []
        var summaries: [ConversationRosterSummary] = []
        var pages = 0
        var reachedEnd = false
        var stoppedEarly = false
    }

    /// Pages from the first page until `stop` returns `true` for a page, the last page, or the cap.
    /// Throws without returning anything read when a page fails, so a partial read records nothing.
    private func readPages(_ conversationID: ConversationID, stop: (FlipClient.RosterPage) -> Bool) async throws -> Read {
        var read = Read()
        var pagingToken: Data?
        while read.pages < pageCap {
            let page = try await fetching.getRosterPage(owner: owner, conversationID: conversationID, pagingToken: pagingToken)
            read.pages += 1
            read.members.append(contentsOf: page.members)
            read.summaries.append(page.rosterSummary)
            if stop(page) {
                read.stoppedEarly = true
                break
            }
            guard let next = page.nextPagingToken else {
                read.reachedEnd = true
                break
            }
            pagingToken = next
        }
        return read
    }

    private func logRead(_ message: Logger.Message, _ read: Read, conversationID: ConversationID) {
        logger.info(message, metadata: [
            "conversationID": "\(conversationID)",
            "members": "\(read.members.count)",
            "pages": "\(read.pages)",
            "reachedEnd": "\(read.reachedEnd)",
        ])
    }

    private func report(_ error: Error, reason: String, conversationID: ConversationID) async {
        logger.error("Roster sync failed", metadata: [
            "reason": "\(reason)",
            "conversationID": "\(conversationID)",
            "error": "\(error)",
        ])
        await ErrorReporting.captureError(error, reason: reason)
    }
}
