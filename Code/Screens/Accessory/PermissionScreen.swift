//
//  PermissionScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-06-08.
//

import SwiftUI
import CodeUI

struct PermissionScreen: View {
    
    let image: Image
    let actionTitle: String
    let description: String
    let action: VoidAction
    let skipAction: VoidAction?
    
    // MARK: - Init -
    
    init(image: Image, actionTitle: String, description: String, action: @escaping VoidAction, skipAction: VoidAction? = nil) {
        self.image = image
        self.actionTitle = actionTitle
        self.description = description
        self.action = action
        self.skipAction = skipAction
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    Spacer()
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300)
                    Spacer()
                    Text(description)
                        .font(.appTextMedium)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Spacer()
                }
                Spacer()
                Group {
                    CodeButton(
                        style: .filled,
                        title: actionTitle
                    ) {
                        action()
                    }
                    if let skipAction = skipAction {
                        CodeButton(
                            style: .subtle,
                            title: Localized.Action.notNow
                        ) {
                            skipAction()
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            Analytics.open(screen: .permission)
            ErrorReporting.breadcrumb(.permissionScreen)
        }
    }
}

// MARK: - Templates -

extension PermissionScreen {
    static func forPushNotifications(action: @escaping VoidAction, skipAction: @escaping VoidAction) -> PermissionScreen {
        PermissionScreen(
            image: .asset(.graphicPushPermission),
            actionTitle: Localized.Action.allowPushNotifications,
            description: Localized.Permissions.Description.push,
            action: action,
            skipAction: skipAction
        )
    }
    
    static func forCameraAccess(action: @escaping VoidAction) -> PermissionScreen {
        PermissionScreen(
            image: .asset(.graphicCameraAccess),
            actionTitle: Localized.Action.allowCameraAccess,
            description: Localized.Permissions.Description.camera,
            action: action
        )
    }
}

// MARK: - Previews -

struct PermissionScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PermissionScreen(
                image: .asset(.graphicPushPermission),
                actionTitle: Localized.Action.allowPushNotifications,
                description: Localized.Permissions.Description.push,
                action: {},
                skipAction: {}
            )
            PermissionScreen(
                image: .asset(.graphicCameraAccess),
                actionTitle: Localized.Action.allowCameraAccess,
                description: Localized.Permissions.Description.camera,
                action: {}
            )
        }
    }
}
