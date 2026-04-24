import SwiftUI

struct EngineSectionView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeaderView(title: "Engine", subtitle: "Pick your transcription backend.")

            SettingCardView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Transcription Engine")
                        .font(.headline)

                    Picker("Engine", selection: $model.settings.engine) {
                        Text("Local Whisper (whisper.cpp)").tag(Engine.localWhisper)
                        Text("Apple Speech (on-device)").tag(Engine.appleSpeech)
                        Text("OpenAI API").tag(Engine.openAI)
                        Text("Groq API").tag(Engine.groq)
                        Text("Anthropic API (not STT)").tag(Engine.anthropic)
                        Text("Local Model (Core ML)").tag(Engine.localModel)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    .onChange(of: model.settings.engine) { _, _ in
                        model.queuePersistSettings()
                    }

                    if model.settings.engine == .localWhisper {
                        Divider().opacity(0.25)
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Model Size")
                                    .font(.headline)
                                Picker("Model", selection: $model.settings.whisperModel) {
                                    Text("Small (~466 MB)").tag(WhisperModel.small)
                                    Text("Medium (~1.5 GB)").tag(WhisperModel.medium)
                                }
                                .labelsHidden()
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 10) {
                                Button {
                                    Task { await model.downloadSelectedModel() }
                                } label: {
                                    Text(model.isSelectedModelDownloaded ? "✓" : "Download")
                                        .frame(minWidth: 92)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isSelectedModelDownloaded || model.downloadState.isBusy)

                                if case .downloading(let phase, let pct) = model.downloadState {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(phase)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ProgressView(value: pct)
                                            .frame(width: 200)
                                    }
                                }
                            }
                        }
                    } else if model.settings.engine == .groq {
                        Divider().opacity(0.25)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Groq API Key")
                                .font(.headline)
                            SecureField("gsk_…", text: $model.settings.groqApiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 420)
                            Text("Used for `https://api.groq.com/openai/v1/audio/transcriptions`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: model.settings.groqApiKey) { _, _ in
                            model.queuePersistSettings()
                        }
                    } else if model.settings.engine == .openAI {
                        Divider().opacity(0.25)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenAI API Key")
                                .font(.headline)
                            SecureField("sk-…", text: $model.settings.openAIApiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 420)
                            Text("Used for `https://api.openai.com/v1/audio/transcriptions`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: model.settings.openAIApiKey) { _, _ in
                            model.queuePersistSettings()
                        }
                    } else if model.settings.engine == .anthropic {
                        Divider().opacity(0.25)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anthropic API Key")
                                .font(.headline)
                            SecureField("sk-ant-…", text: $model.settings.anthropicApiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 420)
                            Text("Anthropic doesn’t provide audio transcription. This option is reserved for future “rewrite with Claude” after STT.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: model.settings.anthropicApiKey) { _, _ in
                            model.queuePersistSettings()
                        }
                    } else if model.settings.engine == .localModel {
                        Divider().opacity(0.25)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Local Model Identifier")
                                .font(.headline)
                            TextField("e.g. com.yourapp.whisper-coreml", text: $model.settings.localModelIdentifier)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 420)
                            Text("Placeholder: wire a Core ML speech-to-text pipeline here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: model.settings.localModelIdentifier) { _, _ in
                            model.queuePersistSettings()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .onChange(of: model.settings.whisperModel) { _, _ in
            model.queuePersistSettings()
        }
    }
}

