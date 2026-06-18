//
//  ApplicationLogsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ApplicationLogsScreen: View {

    @State private var exportedLogs: URL?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "doc.text")
                    .font(.system(size: 70, weight: .thin))
                    .foregroundStyle(Color.textMain)
                    .padding(24)

                VStack(spacing: 12) {
                    Text("Application Logs")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Share a copy of recent app activity with our team to help troubleshoot any issues. No passwords, keys, or personal information are included.")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                Spacer()

                if let exportedLogs {
                    ShareLink(item: exportedLogs) {
                        Text("Share Logs")
                    }
                    .buttonStyle(.filled)
                    .padding(20)
                } else {
                    ProgressView()
                        .padding(20)
                }
            }
        }
        .navigationTitle("Application Logs")
        .toolbarTitleDisplayMode(.inline)
        .task {
            exportedLogs = try? await LogStore.shared.exportLogs()
        }
    }
}
