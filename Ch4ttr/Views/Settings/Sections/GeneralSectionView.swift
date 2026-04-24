import SwiftUI

struct GeneralSectionView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeaderView(title: "General", subtitle: "Choose your audio input device.")

            SettingCardView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Microphone")
                        .font(.headline)
                    Picker("Microphone", selection: $model.settings.microphone) {
                        ForEach(model.microphones, id: \.name) { mic in
                            Text(mic.displayName).tag(mic.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 420)

                    Text("Select your preferred input device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingCardView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Language")
                        .font(.headline)
                    Picker("Language", selection: $model.settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 420)

                    Text("Used for both local and cloud transcription, and text cleanup rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .onChange(of: model.settings.microphone) { _, _ in
            model.queuePersistSettings()
        }
        .onChange(of: model.settings.language) { _, _ in
            model.queuePersistSettings()
        }
    }
}

