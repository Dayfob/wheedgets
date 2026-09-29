import SwiftUI
import WheedgetsCore

struct DrumPanelView: View {
    let drums: DrumKit
    let host: WidgetHost
    let openSettings: @MainActor () -> Void

    private static let columnCount = 4
    private static let spacing: CGFloat = 8
    private static let padding: CGFloat = 14
    private static var width: CGFloat {
        CGFloat(columnCount) * PadCell.size.width + CGFloat(columnCount - 1) * spacing + padding * 2
    }

    var body: some View {
        VStack(spacing: 12) {
            WidgetHeader(host: host, openSettings: openSettings) {
                if drums.settings.control == .keyboard {
                    PanelIconButton(
                        systemImage: drums.settings.keyHandling == .capture ? "keyboard.badge.eye" : "keyboard",
                        help: drums.settings.keyHandling == .capture
                            ? "Bound keys are captured. Click to let them type too."
                            : "Bound keys also type. Click to capture them."
                    ) {
                        drums.settings.keyHandling = drums.settings.keyHandling == .capture ? .passThrough : .capture
                    }
                }
                PanelIconButton(systemImage: "xmark", help: "Hide Pads") {
                    drums.settings.showsPanel = false
                }
            }
            if drums.settings.control == .trackpad && drums.settings.trackpad.layout == .custom {
                CustomZonesView(
                    zones: drums.settings.trackpad.customZones,
                    hitTokens: drums.customZoneHitTokens,
                    onTap: { drums.playCustomZone($0) },
                    darkBackground: true
                )
                .frame(width: Self.width - Self.padding * 2)
            } else if drums.settings.control == .trackpad {
                TrackpadZonesView(drums: drums, width: Self.width - Self.padding * 2)
            } else if drums.settings.pads.isEmpty {
                Text("No pads yet. Add some in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(PadCell.size.width), spacing: Self.spacing), count: Self.columnCount),
                    spacing: Self.spacing
                ) {
                    ForEach(drums.settings.pads) { pad in
                        PadCell(pad: pad, hitToken: drums.hitTokens[pad.id] ?? 0) {
                            drums.trigger(pad)
                        }
                    }
                }
            }
            VolumeSlider(value: Binding(
                get: { drums.settings.volume },
                set: { drums.settings.volume = $0 }
            ))
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .background(PanelBackground(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }
}

/// The trackpad's drum zones, laid out like the trackpad itself.
private struct TrackpadZonesView: View {
    let drums: DrumKit
    let width: CGFloat

    private let spacing: CGFloat = 6

    var body: some View {
        let grid = drums.settings.trackpad
        // A trackpad is about 1.6 times wider than tall.
        let height = width / 1.6
        let cellWidth = (width - spacing * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
        let cellHeight = (height - spacing * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        VStack(spacing: spacing) {
            ForEach(0..<grid.rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<grid.columns, id: \.self) { column in
                        let index = row * grid.columns + column
                        ZoneCell(
                            source: grid.zones[index],
                            size: CGSize(width: cellWidth, height: cellHeight),
                            hitToken: drums.zoneHitTokens[index] ?? 0
                        ) {
                            drums.playZone(index)
                        }
                    }
                }
            }
        }
        .frame(width: width, height: height)
    }
}

private struct ZoneCell: View {
    let source: SoundSource
    let size: CGSize
    let hitToken: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(source.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(6)
                .frame(width: size.width, height: size.height)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(source.tint.gradient.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: 0.0, trigger: hitToken) { content, glow in
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(glow * 0.5))
                        .allowsHitTesting(false)
                )
                .scaleEffect(1 - glow * 0.04)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: 0.02)
                CubicKeyframe(0.0, duration: 0.3)
            }
        }
    }
}

struct PadCell: View {
    static let size = CGSize(width: 76, height: 66)

    let pad: Pad
    let hitToken: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(KeyNames.name(for: pad.keyCode))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.3), in: Capsule())
                Spacer(minLength: 0)
                Text(pad.source.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(7)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(pad.source.tint.gradient.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: 0.0, trigger: hitToken) { content, glow in
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(glow * 0.5))
                        .allowsHitTesting(false)
                )
                .scaleEffect(1 - glow * 0.06)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: 0.02)
                CubicKeyframe(0.0, duration: 0.3)
            }
        }
        .accessibilityLabel(Text(verbatim: "\(pad.source.displayName), \(KeyNames.name(for: pad.keyCode))"))
    }
}
