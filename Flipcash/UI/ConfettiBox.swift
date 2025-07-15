//
//  ConfettiBox.swift
//  Code
//
//  Created by Dima Bart on 2025-07-15.
//

import SwiftUI
import ConfettiSwiftUI

struct ConfettiBox: View {

    @Binding var trigger: Int
    
    init(trigger: Binding<Int>) {
        self._trigger = trigger
    }
    
    var body: some View {
        VStack {
            
        }
        .confettiCannon(
            trigger: $trigger,
            num: 100,
            confettis: [
//                .shape(.circle),
//                .shape(.triangle),
                .shape(.square),
                .shape(.slimRectangle),
//                .shape(.roundedCross),
            ],
//            colors: <#T##[Color]#>,
            confettiSize: 10,
//            rainHeight: <#T##CGFloat#>,
            fadesOut: true,
            opacity: 1.0,
            openingAngle: .degrees(45),
            closingAngle: .degrees(135),
//            radius: <#T##CGFloat#>,
            repetitions: 3,
            repetitionInterval: 0.7,
            hapticFeedback: true
        )
    }
}
