//
//  AppMain.swift
//  Flipcash
//
//  Created by Dima Bart on 2025-03-31.
//

import SwiftUI
import FlipcashUI
import Firebase

//@main
//struct AppMain: App {
//    
//    @Environment(\.scenePhase) private var scenePhase
//    
//    
//    private var isAppBackgrounded: Bool {
//        scenePhase == .background || scenePhase == .inactive
//    }
//    
//    // MARK: - Init -
//    
//    init() {        
//        
//        
//    }
//    
//    // MARK: - Body -
//    
//    var body: some Scene {
//        WindowGroup {
//            ContainerScreen(container: container)
//                .injectingEnvironment(from: container)
//                .colorScheme(.dark)
//                .tint(Color.textMain)
//                .onOpenURL(perform: openURL)
//        }
//    }
//    
//    private func openURL(url: URL) {
//        let action = container.deepLinkController.handle(open: url)
//        Task {
//            try await action?.executeAction()
//        }
//    }
//}
