//
//  Array+Keyed.swift
//  Code
//
//  Created by Dima Bart on 2022-04-01.
//

import Foundation

extension Array {
    func elementsKeyed<T>(by keyPath: KeyPath<Element, T>) -> [T: Element] where T: Hashable {
        var container: [T: Element] = [:]
        for element in self {
            let key = element[keyPath: keyPath]
            container[key] = element
        }
        return container
    }
}
