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
        setData: (C) -> Void
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

            performBatchUpdates({
                setData(changeset.data)
                dispatchGroup?.enter()

                if !changeset.elementDeleted.isEmpty {
                    deleteItems(at: changeset.elementDeleted.map { IndexPath(item: $0.element, section: $0.section) })
                }
                if !changeset.elementInserted.isEmpty {
                    insertItems(at: changeset.elementInserted.map { IndexPath(item: $0.element, section: $0.section) })
                }
                if !changeset.elementUpdated.isEmpty {
                    let indexPaths = changeset.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) }
                    reconfigureItems(at: indexPaths)
                    (collectionViewLayout as? CollectionViewChatLayout)?.reconfigureItems(at: indexPaths)
                }
                for (source, target) in changeset.elementMoved {
                    moveItem(at: IndexPath(item: source.element, section: source.section), to: IndexPath(item: target.element, section: target.section))
                }
            }, completion: completionHandler)
        }
        dispatchGroup?.notify(queue: .main) { completion!(true) }
    }
}

extension StagedChangeset {

    /// DifferenceKit splits actions into separate changesets to work around `UICollectionView`
    /// limitations, which can leave the layout unable to see that an insert and delete happen
    /// together. Deletions and insertions can be processed together, so flatten that case.
    func flattenIfPossible() -> StagedChangeset {
        if count == 2,
           self[0].sectionChangeCount == 0,
           self[1].sectionChangeCount == 0,
           self[0].elementDeleted.count == self[0].elementChangeCount,
           self[1].elementInserted.count == self[1].elementChangeCount {
            return StagedChangeset(arrayLiteral: Changeset(data: self[1].data, elementDeleted: self[0].elementDeleted, elementInserted: self[1].elementInserted))
        }
        return self
    }
}
#endif
