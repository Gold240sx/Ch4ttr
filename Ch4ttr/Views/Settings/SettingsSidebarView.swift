import SwiftUI

struct SettingsSidebarView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 30, height: 30)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ch4ttr")
                        .font(.system(.headline, design: .rounded))
                    StatusPillView(state: model.recordingState)
                }
                Spacer(minLength: 0)
            }

            if let _ = model.selectedUserId {
                Picker("User", selection: Binding(
                    get: { model.selectedUserId! },
                    set: { model.queueSelectUser($0) }
                )) {
                    ForEach(model.users) { u in
                        Text(u.name).tag(u.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            List(selection: Binding(
                get: { model.selectedSection },
                set: { new in
                    Task { @MainActor in
                        model.selectedSection = new
                    }
                }
            )) {
                Label("General", systemImage: "slider.horizontal.3")
                    .tag(SettingsSection.general)
                Label("Engine", systemImage: "waveform.badge.magnifyingglass")
                    .tag(SettingsSection.engine)
                Label("Recording", systemImage: "keyboard.badge.ellipsis")
                    .tag(SettingsSection.recording)
                Label("Permissions", systemImage: "hand.raised.fill")
                    .tag(SettingsSection.permissions)
                Label("Dictionary", systemImage: "character.book.closed")
                    .tag(SettingsSection.dictionary)
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            Text("v0.1.0")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.windowBackground)
    }
}

