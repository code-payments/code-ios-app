//
//  MigrationScreen.swift
//  Code
//
//  Created by Dima Bart on 2022-02-09.
//

import SwiftUI
import CodeUI

struct MigrationScreen: View {
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                Image.asset(.codeLogo)
                    .resizable()
                    .aspectRatio(1.0, contentMode: .fit)
                    .frame(width: 100, height: 100, alignment: .center)
                LoadingView(color: .textMain)
                    .offset(x: 0, y: 90)
            }
        }
        .onAppear {
            Analytics.open(screen: .migration)
            ErrorReporting.breadcrumb(.migrationScreen)
        }
    }
}

// MARK: - Previews -

struct MigrationScreen_Previews: PreviewProvider {
    static var previews: some View {
        MigrationScreen()
            .preferredColorScheme(.dark)
    }
}
