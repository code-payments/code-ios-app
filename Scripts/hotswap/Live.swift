// The live patch. Save this file and watch.py compiles it into a dylib that the Debug app loads.
// Each replacement restates the body of a function in the Flipcash module.

@testable import Flipcash
import SwiftUI
import FlipcashCore
import FlipcashUI

extension ArchivedRow {
    @_dynamicReplacement(for: body)
    var patched_body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .frame(minWidth: 45)
                Text("Archived (live)")
                    .font(.appTextMedium)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.appTextSmall)
                }
                Image(systemName: "chevron.right")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 12)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
