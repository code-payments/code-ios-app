//
//  UICollectionView+Reload.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//
//  Adapted from the ChatLayout example's DifferenceKit+Extension.swift
//  (https://github.com/ekazaev/ChatLayout, MIT) — the canonical way to apply a `StagedChangeset`
//  to a `UICollectionView` so `CollectionViewChatLayout`'s keep-at-bottom anchoring engages.
//

#if canImport(UIKit)
import ChatLayout
import DifferenceKit
import SwiftUI
import UIKit

extension UICollectionView {

    /// Apply a `StagedChangeset` as batch updates. Falls back to a full reload (via
    /// `onInterruptedReload`) when off-screen or when `interrupt` trips on a change too large to
    /// animate. This is what lets `keepContentOffsetAtBottomOnBatchUpdates` keep new content pinned.
    ///
    /// `animatingWith` times each batch transaction on the caller's spring; nil rides UIKit's
    /// stock curve.
    func reload<C>(
        using stagedChangeset: StagedChangeset<C>,
        animatingWith spring: Spring? = nil,
        interrupt: ((Changeset<C>) -> Bool)? = nil,
        onInterruptedReload: (() -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil,
        setData: @escaping (C) -> Void
    ) {
        let fallbackReload = { (data: C) in
            setData(data)
            if let onInterruptedReload {
                onInterruptedReload()
            } else {
                self.reloadData()
            }
            completion?(false)
        }

        if window == nil, let data = stagedChangeset.last?.data {
            fallbackReload(data)
            return
        }

        // Interrupt is decided up front, before any stage starts animating — the fallback's
        // reload + re-anchor must never run while an earlier stage's animation is in flight.
        if let interrupt, stagedChangeset.contains(where: interrupt), let data = stagedChangeset.last?.data {
            fallbackReload(data)
            return
        }

        let dispatchGroup: DispatchGroup? = completion != nil ? DispatchGroup() : nil
        let completionHandler: ((Bool) -> Void)? = completion != nil ? { _ in dispatchGroup!.leave() } : nil

        for changeset in stagedChangeset {
            let updates = {
                setData(changeset.data)
                dispatchGroup?.enter()

                if !changeset.elementDeleted.isEmpty {
                    self.deleteItems(at: changeset.elementDeleted.map { IndexPath(item: $0.element, section: $0.section) })
                }
                if !changeset.elementInserted.isEmpty {
                    self.insertItems(at: changeset.elementInserted.map { IndexPath(item: $0.element, section: $0.section) })
                }
                if !changeset.elementUpdated.isEmpty {
                    let indexPaths = changeset.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) }
                    self.reconfigureItems(at: indexPaths)
                    (self.collectionViewLayout as? CollectionViewChatLayout)?.reconfigureItems(at: indexPaths)
                }
                for (source, target) in changeset.elementMoved {
                    self.moveItem(at: IndexPath(item: source.element, section: source.section), to: IndexPath(item: target.element, section: target.section))
                }
            }

            if let spring {
                // The group waits for the spring to settle, not just the batch to commit —
                // `completion` means no animated layout work remains.
                dispatchGroup?.enter()
                UIView.animate(springDuration: spring.duration, bounce: spring.bounce, options: [.allowUserInteraction], animations: {
                    self.performBatchUpdates(updates, completion: completionHandler)
                }, completion: { _ in
                    dispatchGroup?.leave()
                })
            } else {
                performBatchUpdates(updates, completion: completionHandler)
            }
        }
        dispatchGroup?.notify(queue: .main) { completion!(true) }
    }
}

extension StagedChangeset {

    /// DifferenceKit packages one diff into up to three stages — `[updates]`, `[deletes]`,
    /// `[inserts+moves]` — applied as separate batch updates. Applied that way, a receipt or
    /// grouping change landing with an insert runs 2–3 overlapping animated batch updates, and
    /// `CollectionViewChatLayout` computes its keep-at-bottom compensation per batch — the overlap
    /// is what slid transcript cells in from random directions.
    ///
    /// Merging is index-safe whenever no stage carries moves or section changes: updated and
    /// deleted indices come out of the single underlying diff in *source* coordinates and inserted
    /// indices in *target* coordinates — exactly the before/after semantics of one
    /// `performBatchUpdates`. A move's source index is relative to the post-delete stage instead,
    /// so any stage with moves keeps the staged application.
    func flattenIfPossible() -> StagedChangeset {
        guard count > 1,
              let target = last?.data,
              allSatisfy({ $0.sectionChangeCount == 0 && $0.elementMoved.isEmpty }) else { return self }
        return [Changeset(
            data: target,
            elementDeleted: flatMap(\.elementDeleted),
            elementInserted: flatMap(\.elementInserted),
            elementUpdated: flatMap(\.elementUpdated)
        )]
    }
}
#endif
