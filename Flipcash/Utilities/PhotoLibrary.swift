//
//  PhotoLibrary.swift
//  Code
//
//  Created by Dima Bart on 2022-01-07.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

enum PhotoLibrary {
    nonisolated static func write(image: UIImage, completion: @escaping @Sendable (Error?) -> Void) {
        let writer = Writer(completion: completion)
        writer.writeImage(image)
    }
    
    static func saveSecretRecoveryPhraseSnapshot(for mnemonic: MnemonicPhrase) async throws {
        let snapshot = createSnapshotImage(mnemonic: mnemonic)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) -> Void in
            DispatchQueue.global(qos: .background).async {
                PhotoLibrary.write(image: snapshot) { error in
                    if let error = error {
                        c.resume(throwing: error)
                    } else {
                        c.resume(returning: ())
                    }
                }
            }
        }
    }
    
    private static func createSnapshotImage(mnemonic: MnemonicPhrase) -> UIImage {
        let controller = UIHostingController(rootView: Snapshot(mnemonic: mnemonic))
        
        let rect = CGRect.iPhone13
        let view = controller.view!
        view.backgroundColor = .background
        view.bounds = rect
        
        let renderer = UIGraphicsImageRenderer(bounds: rect)
        return renderer.image { _ in
            _ = view.drawHierarchy(in: rect, afterScreenUpdates: true)
        }
    }
}

// MARK: - Writer -

private extension PhotoLibrary {
    nonisolated final class Writer: NSObject {

        let completion: @Sendable (Error?) -> Void

        init(completion: @escaping @Sendable (Error?) -> Void) {
            self.completion = completion
            super.init()
        }

        func writeImage(_ image: UIImage) {
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveComplete(_:didFinishSavingWithError:contextInfo:)), nil)
        }

        @objc func saveComplete(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
            completion(error)
        }
    }
}
