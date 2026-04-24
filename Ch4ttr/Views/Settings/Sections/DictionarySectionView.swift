import SwiftUI

struct DictionarySectionView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var newPhrase: String = ""
    @State private var newReplacement: String = ""
    @State private var newStrength: Double = 0.65

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeaderView(title: "Dictionary", subtitle: "Per-user, offline text fixes applied after transcription.")

            SettingCardView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Phrase (heard)", text: $newPhrase)
                                .textFieldStyle(.roundedBorder)
                            TextField("Replacement", text: $newReplacement)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                let phrase = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
                                if phrase.isEmpty { return }
                                model.dictionary.insert(
                                    DictionaryEntry(
                                        phrase: phrase,
                                        replacement: newReplacement,
                                        replacementStrength: newStrength
                                    ),
                                    at: 0
                                )
                                newPhrase = ""
                                newReplacement = ""
                                newStrength = 0.65
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        HStack(spacing: 10) {
                            Text("Strength")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: $newStrength, in: 0...1, step: 0.05)
                                .frame(maxWidth: 220)
                            Text(strengthLabel(newStrength))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 78, alignment: .leading)
                        }
                    }

                    if model.dictionary.isEmpty {
                        Text("No entries yet. Add phrases you commonly say (or mis-transcriptions) and your preferred replacements.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach($model.dictionary) { $entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Toggle("", isOn: $entry.isEnabled)
                                            .labelsHidden()
                                        TextField("Phrase", text: $entry.phrase)
                                        TextField("Replacement", text: $entry.replacement)
                                    }

                                    HStack(spacing: 10) {
                                        Text("Strength")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 58, alignment: .leading)
                                        Slider(value: $entry.replacementStrength, in: 0...1, step: 0.05)
                                        Text(strengthLabel(entry.replacementStrength))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 78, alignment: .leading)
                                    }
                                    .padding(.leading, 28)
                                }
                                .padding(.vertical, 4)
                            }
                            .onDelete { idx in
                                model.dictionary.remove(atOffsets: idx)
                            }
                        }
                        .frame(minHeight: 280)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func strengthLabel(_ strength: Double) -> String {
        switch strength {
        case ..<0.34:
            return "Cautious"
        case ..<0.72:
            return "Balanced"
        default:
            return "Aggressive"
        }
    }
}
