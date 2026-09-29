import Foundation
import Testing
@testable import WheedgetsCore

struct DrumTrackpadSettingsTests {
    @Test func defaultsToTwoByFourWithKickAndSnareBottomLeft() {
        let grid = DrumTrackpadSettings()
        #expect(grid.rows == 2 && grid.columns == 4)
        #expect(grid.zones.count == 8)
        #expect(grid.zone(row: 1, column: 0) == .builtin(.kick))
        #expect(grid.zone(row: 1, column: 1) == .builtin(.snare))
    }

    @Test func pointsMapToZonesWithTopRowFirst() {
        let grid = DrumTrackpadSettings()
        #expect(grid.zoneIndex(x: 0.05, y: 0.95) == 0, "top left")
        #expect(grid.zoneIndex(x: 0.95, y: 0.95) == 3, "top right")
        #expect(grid.zoneIndex(x: 0.05, y: 0.05) == 4, "bottom left")
        #expect(grid.zoneIndex(x: 1.0, y: 0.0) == 7, "edges clamp inside")
    }

    @Test func oneSoundCanFillSeveralZones() {
        var grid = DrumTrackpadSettings()
        grid.setZone(row: 1, column: 2, to: .builtin(.kick))
        #expect(grid.zones.filter { $0 == .builtin(.kick) }.count == 2)
    }

    @Test func resizingKeepsAssignedSounds() {
        var grid = DrumTrackpadSettings()
        grid.setZone(row: 0, column: 0, to: .builtin(.cowbell))
        grid.resize(rows: 3, columns: 2)
        #expect(grid.zones.count == 6)
        #expect(grid.zone(row: 0, column: 0) == .builtin(.cowbell))
        grid.resize(rows: 9, columns: 0)
        #expect(grid.rows == 4 && grid.columns == 1, "clamped to 1…4")
        #expect(grid.zone(row: 0, column: 0) == .builtin(.cowbell))
    }

    @Test func decodingRepairsAMismatchedGrid() throws {
        let json = #"{"rows": 2, "columns": 2, "zones": [{"builtin": {"_0": "kick"}}]}"#
        let grid = try JSONDecoder().decode(DrumTrackpadSettings.self, from: Data(json.utf8))
        #expect(grid.zones.count == 4)
        #expect(grid.zones[0] == .builtin(.kick))
    }

    @Test func zoneSamplesCountAsInUse() {
        var drums = DrumSettings(pads: [])
        var grid = drums.trackpad
        grid.setZone(row: 0, column: 0, to: .sample(fileName: "a.wav", displayName: "A"))
        drums.trackpad = grid
        #expect(drums.referencedSampleFiles == ["a.wav"])
    }
}

struct TrackpadHitDetectorTests {
    private func contact(_ id: Int32, size: Double) -> TrackpadHitDetector.Contact {
        .init(id: id, x: 0.5, y: 0.5, size: size)
    }

    @Test func aFingerHitsOnceOnItsSecondFrame() {
        var detector = TrackpadHitDetector()
        #expect(detector.update(contacts: [contact(1, size: 0.3)]).isEmpty, "landing frame: still measuring")
        #expect(detector.update(contacts: [contact(1, size: 0.6)]).count == 1)
        #expect(detector.update(contacts: [contact(1, size: 0.7)]).isEmpty, "held, not hit again")
        _ = detector.update(contacts: [])
        _ = detector.update(contacts: [contact(1, size: 0.3)])
        #expect(detector.update(contacts: [contact(1, size: 0.6)]).count == 1, "lifted and tapped again")
    }

    /// Sizes one frame after touchdown, recorded on a real trackpad.
    @Test func recordedTapsSpreadFromSoftToHard() throws {
        func hit(_ first: Double, _ second: Double) throws -> Double {
            var detector = TrackpadHitDetector()
            _ = detector.update(contacts: [contact(1, size: first)])
            return try #require(detector.update(contacts: [contact(1, size: second)]).first).strength
        }
        let featherLight = try hit(0.10, 0.13)
        let soft = try hit(0.10, 0.41)
        let hard = try hit(0.93, 0.95)
        #expect(featherLight < 0.25)
        #expect(soft > 0.3 && soft < 0.55)
        #expect(hard > 0.95)
    }

    @Test func aTapLiftedAfterOneFrameStillHitsSoftly() throws {
        var detector = TrackpadHitDetector()
        #expect(detector.update(contacts: [contact(1, size: 0.09)]).isEmpty)
        let hit = try #require(detector.update(contacts: []).first)
        #expect(hit.strength < 0.2)
    }

    @Test func noiseIsNotAHit() {
        var detector = TrackpadHitDetector()
        _ = detector.update(contacts: [contact(1, size: 0.01)])
        #expect(detector.update(contacts: [contact(1, size: 0.02)]).isEmpty)
    }

    @Test func aHarderFingerRaisesTheCeiling() {
        var detector = TrackpadHitDetector()
        #expect(detector.strength(for: 1.4) == 1)
        #expect(detector.strength(for: 0.9) < 0.7)
    }
}
