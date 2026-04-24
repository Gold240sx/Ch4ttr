//
//  Ch4ttrApp.swift
//  Ch4ttr
//
//  Created by Michael Martell on 4/24/26.
//

import SwiftUI

@main
struct Ch4ttrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppViewModel

    init() {
        _appModel = StateObject(wrappedValue: .shared)
    }

    var body: some Scene {
        MenuBarExtra {
            Button("Open Settings…") {
                SettingsWindowController.shared.show(with: appModel)
            }
            Button("Mini Recorder") {
                MiniRecorderController.shared.show()
            }
            Divider()
            Button("Toggle Recording") {
                Task { await appModel.toggleRecordingFromUI() }
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            MenuBarIcon(state: appModel.recordingState)
        }

        .menuBarExtraStyle(.menu)

        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    Task { @MainActor in
                        appDelegate.appModel = appModel
                    }
                }
        }
    }
}

private struct MenuBarIcon: View {
    let state: RecordingState

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .symbolEffect(.pulse, options: .repeating, isActive: state == .recording)
    }

    private var symbolName: String {
        switch state {
        case .standby: return "waveform.circle"
        case .recording: return "record.circle.fill"
        case .analyzing: return "waveform.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .standby: return .primary
        case .recording: return .red
        case .analyzing: return .orange
        }
    }
}

