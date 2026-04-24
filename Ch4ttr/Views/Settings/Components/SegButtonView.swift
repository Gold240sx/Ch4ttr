import SwiftUI

struct SegButtonView: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 120)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

