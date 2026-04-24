//
//  ContentView.swift
//  Ch4ttr
//
//  Created by Michael Martell on 4/24/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        SettingsRootView()
    }
}

// Most of the settings UI moved into `Views/Settings/` to keep MVVM boundaries clean.

#Preview {
    ContentView()
        .environmentObject(AppViewModel.shared)
}

