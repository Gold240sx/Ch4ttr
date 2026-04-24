import SwiftUI

struct StatusPillView: View {
    let state: RecordingState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var color: Color {
        switch state {
        case .standby: return .green.opacity(0.85)
        case .recording: return .red.opacity(0.9)
        case .analyzing: return .orange.opacity(0.9)
        }
    }

    private var label: String {
        switch state {
        case .standby: return "Standby"
        case .recording: return "Recording…"
        case .analyzing: return "Analyzing…"
        }
    }
}

