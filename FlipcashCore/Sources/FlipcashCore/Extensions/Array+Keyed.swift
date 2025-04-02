//
//  Array+Keyed.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Array {
    public func elementsKeyed<T>(by keyPath: KeyPath<Element, T>) -> [T: Element] where T: Hashable {
        var container: [T: Element] = [:]
        for element in self {
            let key = element[keyPath: keyPath]
            container[key] = element
        }
        return container
    }
}
