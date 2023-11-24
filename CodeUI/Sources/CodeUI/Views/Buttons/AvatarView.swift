//
//  AvatarView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct AvatarView: View {
    
    public let initial: String
    public let url: URL?
    public let action: VoidAction
    
    @State private var image: UIImage?
    
    public static let size = CGSize(width: 42, height: 42)
    
    // MARK: - Init -
    
    public init(name: String, url: URL?, action: @escaping VoidAction) {
        self.initial = String(name.uppercased().first ?? "1")
        self.url = url
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                    Text(initial)
                        .foregroundColor(.white)
                        .font(.default(size: 22, weight: .medium))
                }
            }
        }
        .frame(width: AvatarView.size.width, height: AvatarView.size.height, alignment: .center)
//        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 1)
        .onAppear {
            if let url = url {
                ImageLoader.shared.load(url) { image in
                    if let image = image {
                        self.image = image
                    }
                }
            }
        }
    }
}

// MARK: - Image Loader -

class ImageLoader {
    
    static let shared = ImageLoader()
    
    private init() {}
    
    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard
                let data = data,
                let image = UIImage(data: data)
            else {
                completion(nil)
                return
            }
            
            completion(image)
        }
        task.resume()
    }
}

// MARK: - Previews -

struct AvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            AvatarView(name: "Dima", url: nil) {}
            AvatarView(name: "Jack", url: nil) {}
            AvatarView(name: "Walter", url: nil) {}
        }
        .previewLayout(.fixed(width: 200.0, height: 200.0))
    }
}

#endif
