//
//  ApplicationLogsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ApplicationLogsScreen: View {

    @State private var isExporting = false

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

                    Text("Share a copy of recent app activity with our team to help troubleshoot any issues.\n\nNo passwords, keys, or personal information are included.")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button {
                    isExporting = true
                    Task {
                        defer { isExporting = false }
                        if let url = try? await LogStore.shared.exportLogs() {
                            ShareSheet.present(url: url)
                        }
                    }
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Text("Share Logs")
                    }
                }
                .buttonStyle(.filled)
                .disabled(isExporting)
                .padding(20)
            }
        }
        .navigationTitle("Application Logs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
