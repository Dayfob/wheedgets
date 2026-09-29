import WheedgetsCore
import SwiftUI

/// Master volume, 0–200 %. Drawn by hand instead of `Slider` because it lives
/// in a panel that never becomes key, where a plain drag gesture is reliable.
struct VolumeSlider: View {
    @Binding var value: Float

    var range: ClosedRange<Float> = Volume.module

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: speakerSymbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                let width = geometry.size.width
                let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(value > 1 ? Color.orange : Color.accentColor)
                        .frame(width: max(6, width * fraction))
                    // Marks 100 %: above it, gain goes through the limiter.
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 1, height: 10)
                        .offset(x: width * CGFloat((1 - range.lowerBound) / (range.upperBound - range.lowerBound)))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = Float(drag.location.x / max(width, 1))
                    value = Self.snapped(range.lowerBound + position * (range.upperBound - range.lowerBound), in: range)
                })
            }
            .frame(height: 20)
            Text(verbatim: "\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Volume"))
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = (value + 0.1).clamped(to: range)
            case .decrement: value = (value - 0.1).clamped(to: range)
            @unknown default: break
            }
        }
    }

    private var speakerSymbol: String {
        switch value {
        case 0: "speaker.slash.fill"
        case ..<0.5: "speaker.wave.1.fill"
        case ..<1.2: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    /// Sticks to 100 % near the middle, so returning to normal is easy.
    static func snapped(_ value: Float, in range: ClosedRange<Float>) -> Float {
        let clamped = value.clamped(to: range)
        return abs(clamped - 1) < 0.04 ? 1 : clamped
    }
}
