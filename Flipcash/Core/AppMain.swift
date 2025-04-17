//
//  AppMain.swift
//  Flipcash
//
//  Created by Dima Bart on 2025-03-31.
//

import SwiftUI
import FlipcashUI

@main
struct AppMain: App {
    
    let container = Container()
    
    // MARK: - Init -
    
    init() {
        FontBook.registerApplicationFonts()
    }
    
    // MARK: - Body -
    
    var body: some Scene {
        WindowGroup {
            ContainerScreen(container: container)
                .injectingEnvironment(from: container)
        }
    }
}
