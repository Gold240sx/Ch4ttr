import AppKit
import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView()
                .navigationSplitViewColumnWidth(min: 225, ideal: 225, max: 300)
        } detail: {
            SettingsDetailView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

