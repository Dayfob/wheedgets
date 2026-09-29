import Foundation
import Testing
@testable import WheedgetsCore

struct DrumZonesTests {
    private func square(_ x0: Double, _ y0: Double, _ size: Double) -> [ZonePoint] {
        [.init(x: x0, y: y0), .init(x: x0 + size, y: y0), .init(x: x0 + size, y: y0 + size), .init(x: x0, y: y0 + size)]
    }

    @Test func pointsInsideAndOutsideAConcaveZone() {
        // An L shape: the notch at the top right is outside.
        let l = CustomZone(outline: [.init(x: 0, y: 0), .init(x: 0.6, y: 0), .init(x: 0.6, y: 0.3),
                                     .init(x: 0.3, y: 0.3), .init(x: 0.3, y: 0.6), .init(x: 0, y: 0.6)],
                           sound: .builtin(.kick))
        #expect(l.contains(.init(x: 0.1, y: 0.1)))
        #expect(l.contains(.init(x: 0.5, y: 0.1)))
        #expect(!l.contains(.init(x: 0.5, y: 0.5)), "inside the notch")
        #expect(!l.contains(.init(x: 0.9, y: 0.9)))
    }

    @Test func laterZonesSitOnTop() {
        var grid = DrumTrackpadSettings()
        grid.customZones = [
            CustomZone(outline: square(0, 0, 0.6), sound: .builtin(.kick)),
            CustomZone(outline: square(0.3, 0.3, 0.6), sound: .builtin(.snare))
        ]
        #expect(grid.customZoneIndex(at: .init(x: 0.1, y: 0.1)) == 0)
        #expect(grid.customZoneIndex(at: .init(x: 0.45, y: 0.45)) == 1, "overlap goes to the later zone")
        #expect(grid.customZoneIndex(at: .init(x: 0.95, y: 0.05)) == nil, "outside every zone: silent")
    }

    @Test func aTracedLoopBecomesACompactOutline() throws {
        // A finger circling, sampled densely with jitter.
        let path = (0..<200).map { i -> ZonePoint in
            let a = Double(i) / 200 * 2 * .pi
            let jitter = (i % 2 == 0 ? 0.002 : -0.002)
            return ZonePoint(x: 0.5 + 0.25 * cos(a) + jitter, y: 0.5 + 0.3 * sin(a))
        }
        let outline = try #require(ZoneTracing.outline(from: path))
        #expect(outline.count < 60, "simplified from 200 points to \(outline.count)")
        let zone = CustomZone(outline: outline, sound: .builtin(.kick))
        #expect(zone.contains(.init(x: 0.5, y: 0.5)))
        #expect(abs(zone.area - .pi * 0.25 * 0.3) < 0.02)
    }

    @Test func scribblesAreNotZones() {
        let line = (0..<50).map { ZonePoint(x: Double($0) / 50, y: 0.5) }
        #expect(ZoneTracing.outline(from: line) == nil, "a straight stroke has no area")
        #expect(ZoneTracing.outline(from: square(0.4, 0.4, 0.05)) == nil, "too small to hit")
    }

    @Test func customZonesSurviveEncodingAndKeepTheirSamples() throws {
        var drums = DrumSettings(pads: [])
        drums.trackpad.layout = .custom
        drums.trackpad.customZones = [CustomZone(outline: square(0, 0, 0.5), sound: .sample(fileName: "z.wav", displayName: "Z"))]
        let decoded = try JSONDecoder().decode(DrumSettings.self, from: JSONEncoder().encode(drums))
        #expect(decoded == drums)
        #expect(decoded.referencedSampleFiles.contains("z.wav"))
    }
}
