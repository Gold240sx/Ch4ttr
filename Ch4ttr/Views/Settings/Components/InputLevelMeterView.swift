import SwiftUI

struct InputLevelMeterView: View {
    let level: Double // 0...1
    var barCount: Int = 12
    var waveform: [Double] = []
    var heightScale: CGFloat = 1
    var isActive: Bool = true

    var body: some View {
        let bars = resolvedBars
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars.count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(opacity(for: i, bars: bars)))
                    .frame(width: 4, height: height(for: i, bars: bars))
                    .animation(.easeOut(duration: 0.08), value: bars[i])
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Input level")
    }

    private var resolvedBars: [Double] {
        guard isActive else {
            return Array(repeating: 0, count: max(8, waveform.count, barCount))
        }

        let clean = waveform.map { $0.clamped(to: 0...1) }
        if clean.count >= 8 {
            return clean
        }
        // Fallback to the original “meter” style driven by scalar level.
        let count = max(8, barCount)
        return (0..<count).map { i in
            let threshold = Double(i + 1) / Double(count)
            return level >= threshold ? 1.0 : (level * Double(count) - Double(i)).clamped(to: 0...1)
        }
    }

    private func height(for index: Int, bars: [Double]) -> CGFloat {
        // Curved profile so it reads as a cohesive wave.
        let t = Double(index) / Double(max(1, bars.count - 1))
        let shape = 0.30 + 0.70 * sin(t * .pi)
        let v = shapedLevel(bars[index])
        let quietDotSize: CGFloat = 4
        return quietDotSize + CGFloat(22 * shape * v) * heightScale
    }

    private func opacity(for index: Int, bars: [Double]) -> Double {
        let v = shapedLevel(bars[index])
        return 0.22 + 0.76 * v
    }

    private func shapedLevel(_ raw: Double) -> Double {
        let gated = ((raw.clamped(to: 0...1) - 0.08) / 0.92).clamped(to: 0...1)
        return pow(gated, 0.62)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
