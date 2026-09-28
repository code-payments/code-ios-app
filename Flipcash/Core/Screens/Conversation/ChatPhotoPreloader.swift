//
//  ChatPhotoPreloader.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit

/// Loads the photos picked in the photo card while they are being picked, so each one is in hand by
/// the time Add stages it.
@MainActor
@Observable
final class ChatPhotoPreloader<Item: Hashable> {

    /// The images that have finished loading, by the item that holds them.
    private(set) var images: [Item: UIImage] = [:]

    @ObservationIgnored private var tasks: [Item: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private let load: (Item) async -> UIImage?

    /// Creates a preloader that reads each item's image through `load`.
    init(load: @escaping (Item) async -> UIImage?) {
        self.load = load
    }

    /// The items being loaded or already loaded.
    var trackedItems: Set<Item> { Set(tasks.keys) }

    /// Starts loading each item in `selection` not yet started, and drops the ones no longer in it.
    func update(selection: [Item]) {
        let selected = Set(selection)
        for item in tasks.keys where !selected.contains(item) {
            tasks.removeValue(forKey: item)?.cancel()
            images.removeValue(forKey: item)
        }
        for item in selection where tasks[item] == nil {
            let task = Task { [load] in await load(item) }
            tasks[item] = task
            Task { [weak self] in
                let image = await task.value
                // Deselected while it loaded, or loaded again under a new task.
                guard let self, self.tasks[item] == task, let image else { return }
                self.images[item] = image
            }
        }
    }

    /// Returns `item`'s image if it has already loaded.
    func loadedImage(for item: Item) -> UIImage? {
        images[item]
    }

    /// Returns `item`'s image, waiting for a load in flight or starting one if none was.
    func image(for item: Item) async -> UIImage? {
        if let image = images[item] { return image }
        if let task = tasks[item] { return await task.value }
        return await load(item)
    }

    /// Cancels every load and lets go of every image.
    func reset() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        images = [:]
    }
}
