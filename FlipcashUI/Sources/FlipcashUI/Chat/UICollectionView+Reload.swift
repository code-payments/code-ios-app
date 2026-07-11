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
        func reloadInstead(with data: C) {
            setData(data)
            if let onInterruptedReload {
                onInterruptedReload()
            } else {
                reloadData()
            }
            completion?(false)
        }

        if case .none = window, let data = stagedChangeset.last?.data {
            reloadInstead(with: data)
            return
        }

        if let batch = stagedChangeset.singleBatch() {
            if let interrupt, interrupt(batch.changeset), let data = stagedChangeset.last?.data {
                reloadInstead(with: data)
                return
            }
            performBatchUpdates({
                if let reconfigureData = batch.reconfigureData {
                    setData(reconfigureData)
                    let indexPaths = batch.changeset.elementUpdated.map { IndexPath(item: $0.element, section: $0.section) }
                    reconfigureItems(at: indexPaths)
                    (collectionViewLayout as? CollectionViewChatLayout)?.reconfigureItems(at: indexPaths)
                }
                setData(batch.changeset.data)
                if !batch.changeset.elementDeleted.isEmpty {
                    deleteItems(at: batch.changeset.elementDeleted.map { IndexPath(item: $0.element, section: $0.section) })
                }
                if !batch.changeset.elementInserted.isEmpty {
                    insertItems(at: batch.changeset.elementInserted.map { IndexPath(item: $0.element, section: $0.section) })
                }
            }, completion: { _ in
                completion?(true)
            })
            return
        }

        // The interrupt fallback must be decided before any batch applies — a mid-sequence
        // `reloadData` lands on in-flight batch animations.
        if let interrupt, stagedChangeset.contains(where: interrupt), let data = stagedChangeset.last?.data {
            reloadInstead(with: data)
            return
        }

        let dispatchGroup: DispatchGroup? = completion != nil ? DispatchGroup() : nil
        let completionHandler: ((Bool) -> Void)? = completion != nil ? { _ in dispatchGroup!.leave() } : nil

        for changeset in stagedChangeset {
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

    /// One `performBatchUpdates` worth of changes: the merged ops over the final target data,
    /// plus the collection the reconfigures resolve against.
    struct SingleBatch {
        let changeset: Changeset<Collection>
        /// The source-shaped collection (updated content, source positions) the data source must
        /// hold while the reconfigures apply, or `nil` when the diff carries no updates — UIKit
        /// resolves them synchronously at source-coordinate index paths.
        let reconfigureData: Collection?
    }

    /// The single-batch form of this diff, or `nil` when a stage carries moves or section
    /// changes — a move's source index is relative to the post-delete stage.
    func singleBatch() -> SingleBatch? {
        guard let target = last?.data,
              allSatisfy({ $0.sectionChangeCount == 0 && $0.elementMoved.isEmpty }) else { return nil }
        let updated = flatMap(\.elementUpdated)
        return SingleBatch(
            changeset: Changeset(
                data: target,
                elementDeleted: flatMap(\.elementDeleted),
                elementInserted: flatMap(\.elementInserted),
                elementUpdated: updated
            ),
            reconfigureData: updated.isEmpty ? nil : first(where: { !$0.elementUpdated.isEmpty })?.data
        )
    }
}
#endif
