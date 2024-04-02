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
    
    public let url: URL?
    public let action: VoidAction?
    
    @State private var image: UIImage?
    
    private let size = CGSize(width: 80, height: 80)
    
    // MARK: - Init -
    
    public init(url: URL?, action: VoidAction?) {
        self.url = url
        self.action = action
    }
    
    public var body: some View {
        Button {
            action?()
        } label: {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
            } else {
                PlaceholderAvatar()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
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

public struct PlaceholderAvatar: View {
    
    private let foregroundColor = Color(r: 97, g: 120, b: 136)
    private let backgroundColor = Color(r: 201, g: 214, b: 222)
    
    public var body: some View {
        VStack(spacing: 6) {
            
            UnevenRoundedCorners(
                tl: 20,
                bl: 15,
                br: 15,
                tr: 20
            )
            .fill(foregroundColor)
            .frame(width: 25, height: 28)
            .padding(.top, 20)
            
            Circle()
                .fill(foregroundColor)
                .frame(width: 50, height: 50)
        }
        .frame(width: 80, height: 80, alignment: .top)
        .background(backgroundColor)
        .mask {
            Circle()
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
            AvatarView(url: nil) {}
            AvatarView(url: nil) {}
            AvatarView(url: nil) {}
        }
        .previewLayout(.fixed(width: 200.0, height: 200.0))
    }
}

#endif
