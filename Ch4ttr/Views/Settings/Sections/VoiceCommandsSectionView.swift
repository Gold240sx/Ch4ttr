import SwiftUI

struct VoiceCommandsSectionView: View {
    private let transcriptCommands: [(phrase: String, effect: String)] = [
        (
            phrase: "Chatter restart",
            effect: "Clears everything dictated in this session before the command. Keeps words spoken after the command."
        ),
        (
            phrase: "Chatter restart paragraph",
            effect: "Keeps text through the last sentence ending (. ! ?), then removes the rest of this session before the command. Optional filler is allowed, e.g. “Chatter restart the paragraph”."
        ),
        (
            phrase: "Chatter start",
            effect: "Clears the transcript so far, then keeps only what you say after the command."
        ),
        (
            phrase: "Chatter end or Chatter stop",
            effect: "Stops recording. Words after the command are ignored."
        ),
    ]

    private let systemCommands: [(phrase: String, effect: String)] = [
        (phrase: "Chatter select all", effect: "Sends ⌘A (select all)."),
        (phrase: "Chatter select paragraph", effect: "Sends ⌥↑ then ⌥⇧↓ to select the current paragraph in many Cocoa-style fields."),
        (phrase: "Chatter select sentence", effect: "Sends ⌥⇧← then ⌥⇧→ to extend the selection around the caret (sentence-like in many editors)."),
        (phrase: "Chatter paste", effect: "Sends ⌘V (pastes the current contents of the general pasteboard)."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeaderView(
                title: "Voice commands",
                subtitle: "While dictating, say Chatter (any casing) then a command. The phrase is removed from the transcript; some commands also send shortcuts in the focused app."
            )

            SettingCardView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trigger")
                        .font(.headline)
                    Text("Speak the word Chatter immediately before the command words. Recognition is case-insensitive.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Example: “…and then Chatter select all to replace it.”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingCardView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Transcript & recording")
                        .font(.headline)

                    ForEach(0..<transcriptCommands.count, id: \.self) { index in
                        let item = transcriptCommands[index]
                        VoiceCommandRow(phrase: item.phrase, effect: item.effect)
                        if index < transcriptCommands.count - 1 {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }

            SettingCardView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Focused app (keyboard)")
                        .font(.headline)
                    Text("Requires Accessibility permission (same as auto-paste). Behavior depends on the frontmost app; paragraph and sentence are best-effort shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(0..<systemCommands.count, id: \.self) { index in
                        let item = systemCommands[index]
                        VoiceCommandRow(phrase: item.phrase, effect: item.effect)
                        if index < systemCommands.count - 1 {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct VoiceCommandRow: View {
    let phrase: String
    let effect: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phrase)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            Text(effect)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
