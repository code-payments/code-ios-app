//
//  FlipchatApp.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-09-24.
//

import SwiftUI
import CodeUI

@main
struct FlipchatApp: App {
    
    @StateObject private var container = AppContainer()
    
    init() {
        FontBook.registerApplicationFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContainerScreen()
                .injectingEnvironment(from: container)
        }
    }
}
