import SwiftUI
import WheedgetsCore

/// The trackpad with its custom drum zones, as drawn by the user.
/// Shared by the pad panel (click to play) and Settings (click to select).
struct CustomZonesView: View {
    let zones: [CustomZone]
    var selected: CustomZone.ID?
    /// A zone being traced right now.
    var draft: [ZonePoint] = []
    var hitTokens: [CustomZone.ID: Int] = [:]
    var onTap: (CustomZone.ID) -> Void = { _ in }
    var darkBackground = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(darkBackground ? Color.white.opacity(0.06) : Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                ForEach(zones) { zone in
                    ZoneShapeView(zone: zone, size: size, isSelected: zone.id == selected, hitToken: hitTokens[zone.id] ?? 0)
                }

                if draft.count > 1 {
                    Path { path in
                        path.addLines(draft.map { point(for: $0, in: size) })
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                if zones.isEmpty && draft.isEmpty {
                    Text("No zones yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let target = ZonePoint(x: location.x / size.width, y: 1 - location.y / size.height)
                // Later zones sit on top, like on the trackpad.
                if let zone = zones.last(where: { $0.contains(target) }) { onTap(zone.id) }
            }
        }
        // A trackpad is about 1.6 times wider than tall.
        .aspectRatio(1.6, contentMode: .fit)
    }

    private func point(for p: ZonePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }
}

private struct ZoneShapeView: View {
    let zone: CustomZone
    let size: CGSize
    let isSelected: Bool
    let hitToken: Int

    var body: some View {
        let outline = Path { path in
            path.addLines(zone.outline.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) })
            path.closeSubpath()
        }
        ZStack {
            outline.fill(zone.sound.tint.opacity(0.45))
            outline.stroke(isSelected ? Color.primary : zone.sound.tint, lineWidth: isSelected ? 3 : 1.5)
            Text(zone.sound.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .position(x: zone.center.x * size.width, y: (1 - zone.center.y) * size.height)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: hitToken) { content, glow in
            content.overlay(outline.fill(.white.opacity(glow * 0.5)).allowsHitTesting(false))
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: 0.02)
                CubicKeyframe(0.0, duration: 0.3)
            }
        }
        .allowsHitTesting(false)
    }
}
