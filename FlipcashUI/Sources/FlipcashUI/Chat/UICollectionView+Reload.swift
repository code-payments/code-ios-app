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
import UIKit

extension UICollectionView {

    /// Apply a `StagedChangeset` as batch updates. Falls back to a full reload (via
    /// `onInterruptedReload`) when off-screen or when `interrupt` trips on a change too large to
    /// animate. This is what lets `keepContentOffsetAtBottomOnBatchUpdates` keep new content pinned.
    func reload<C>(
        using stagedChangeset: StagedChangeset<C>,
        interrupt: ((Changeset<C>) -> Bool)? = nil,
        onInterruptedReload: (() -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil,
        setData: @escaping (C) -> Void
    ) {
        if case .none = window, let data = stagedChangeset.last?.data {
            setData(data)
            if let onInterruptedReload {
                onInterruptedReload()
            } else {
                reloadData()
            }
            completion?(false)
            return
        }

        let dispatchGroup: DispatchGroup? = completion != nil ? DispatchGroup() : nil
        let completionHandler: ((Bool) -> Void)? = completion != nil ? { _ in dispatchGroup!.leave() } : nil

        for changeset in stagedChangeset {
            if let interrupt, interrupt(changeset), let data = stagedChangeset.last?.data {
                setData(data)
                if let onInterruptedReload {
                    onInterruptedReload()
                } else {
                    reloadData()
                }
                completion?(false)
                return
            }

            // The spring context times everything the batch animates — cell shifts, the
            // keep-at-bottom offset compensation, and the delegate's entrance transforms — so the
            // whole transaction moves like the prototype's insertion spring.
            UIView.animate(springDuration: ChatMotion.insertion.duration, bounce: ChatMotion.insertion.bounce, options: [.allowUserInteraction]) {
                self.performBatchUpdates({
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
                }, completion: completionHandler)
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
        return StagedChangeset(arrayLiteral: Changeset(
            data: target,
            elementDeleted: flatMap(\.elementDeleted),
            elementInserted: flatMap(\.elementInserted),
            elementUpdated: flatMap(\.elementUpdated)
        ))
    }
}
#endif
