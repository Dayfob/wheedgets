import Foundation

/// How drums are played. Only one at a time.
public enum DrumControl: String, Codable, CaseIterable, Sendable {
    case keyboard
    /// Zones on the trackpad; nothing is blocked, clicks and the pointer work as usual.
    case trackpad
}

/// What makes a trackpad zone sound.
public enum DrumTrigger: String, Codable, CaseIterable, Sendable {
    /// A finger touching down.
    case tap
    /// A physical click of the trackpad; moving the pointer stays silent.
    case click
}

/// The trackpad as a grid of drum zones.
public struct DrumTrackpadSettings: Codable, Equatable, Sendable {
    public static let sizeRange: ClosedRange<Int> = 1...4

    public private(set) var rows: Int
    public private(set) var columns: Int
    /// One sound per zone, row by row from the top left. Several zones may
    /// share a sound, which makes that drum a bigger target.
    public private(set) var zones: [SoundSource]
    public var layout: DrumZoneLayout
    public var customZones: [CustomZone]
    public var trigger: DrumTrigger
    /// Harder hits play louder.
    public var velocitySensitive: Bool

    public init(
        rows: Int = 2,
        columns: Int = 4,
        zones: [SoundSource]? = nil,
        layout: DrumZoneLayout = .grid,
        customZones: [CustomZone] = [],
        trigger: DrumTrigger = .tap,
        velocitySensitive: Bool = true
    ) {
        self.rows = rows.clamped(to: Self.sizeRange)
        self.columns = columns.clamped(to: Self.sizeRange)
        self.layout = layout
        self.customZones = customZones
        self.trigger = trigger
        self.velocitySensitive = velocitySensitive
        self.zones = []
        self.zones = zones ?? Self.defaultZones(rows: self.rows, columns: self.columns)
        normalizeZones()
    }

    private enum CodingKeys: String, CodingKey { case rows, columns, zones, layout, customZones, trigger, velocitySensitive }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DrumTrackpadSettings()
        self.init(
            rows: try c.decodeIfPresent(Int.self, forKey: .rows) ?? defaults.rows,
            columns: try c.decodeIfPresent(Int.self, forKey: .columns) ?? defaults.columns,
            zones: try? c.decodeIfPresent([SoundSource].self, forKey: .zones),
            layout: (try? c.decodeIfPresent(DrumZoneLayout.self, forKey: .layout)) ?? defaults.layout,
            customZones: (try? c.decodeIfPresent([CustomZone].self, forKey: .customZones)) ?? [],
            trigger: (try? c.decodeIfPresent(DrumTrigger.self, forKey: .trigger)) ?? defaults.trigger,
            velocitySensitive: try c.decodeIfPresent(Bool.self, forKey: .velocitySensitive) ?? defaults.velocitySensitive
        )
    }

    /// Finger-drumming layout: cymbals and toms on top, kick, snare and hats below.
    public static func defaultZones(rows: Int, columns: Int) -> [SoundSource] {
        let reference: [[DrumSound]] = [
            [.crash, .tomHigh, .tomLow, .ride],
            [.kick, .snare, .closedHat, .openHat],
            [.clap, .rim, .tomMid, .cowbell],
            [.kick, .snare, .closedHat, .crash]
        ]
        // Small grids take the most useful drums: the bottom rows first.
        let rowsFromBottom = Array(reference.prefix(max(rows, 2)).reversed().prefix(rows).reversed())
        return rowsFromBottom.flatMap { row in
            (0..<columns).map { SoundSource.builtin(row[$0 % row.count]) }
        }
    }

    public func zone(row: Int, column: Int) -> SoundSource {
        zones[row * columns + column]
    }

    public mutating func setZone(row: Int, column: Int, to source: SoundSource) {
        zones[row * columns + column] = source
    }

    /// Resizes the grid, keeping each zone's sound where the cell still exists.
    public mutating func resize(rows newRows: Int, columns newColumns: Int) {
        let newRows = newRows.clamped(to: Self.sizeRange), newColumns = newColumns.clamped(to: Self.sizeRange)
        let fresh = Self.defaultZones(rows: newRows, columns: newColumns)
        var resized: [SoundSource] = []
        for row in 0..<newRows {
            for column in 0..<newColumns {
                resized.append(row < rows && column < columns
                               ? zone(row: row, column: column)
                               : fresh[row * newColumns + column])
            }
        }
        rows = newRows
        columns = newColumns
        zones = resized
    }

    /// The zone under a point in the trackpad's normalized coordinates (y up).
    public func zoneIndex(x: Double, y: Double) -> Int {
        let column = min(columns - 1, max(0, Int(x * Double(columns))))
        let row = min(rows - 1, max(0, Int((1 - y) * Double(rows))))
        return row * columns + column
    }

    private mutating func normalizeZones() {
        let count = rows * columns
        if zones.count != count {
            let fresh = Self.defaultZones(rows: rows, columns: columns)
            zones = (0..<count).map { $0 < zones.count ? zones[$0] : fresh[$0] }
        }
    }
}

/// Finds drum hits in trackpad frames: each finger touching down is one hit,
/// with a strength from how fast the contact spreads as it lands.
///
/// Measured on a real trackpad: one frame (~8 ms) after touchdown a hard tap
/// already covers about 0.9–1.0 (the framework's size units), a soft tap
/// 0.3–0.6 and a feather-light one 0.1–0.2; later the sizes converge as the
/// finger flattens. So the hit fires on a finger's second frame and reads
/// the size then — one frame of latency for real dynamics.
public struct TrackpadHitDetector: Sendable {
    public struct Contact: Sendable {
        public var id: Int32
        public var x: Double
        public var y: Double
        /// Contact area, in the framework's own units.
        public var size: Double

        public init(id: Int32, x: Double, y: Double, size: Double) {
            self.id = id
            self.x = x
            self.y = y
            self.size = size
        }
    }

    public struct Hit: Equatable, Sendable {
        public var x: Double
        public var y: Double
        /// 0…1.
        public var strength: Double

        public init(x: Double, y: Double, strength: Double) {
            self.x = x
            self.y = y
            self.strength = strength
        }
    }

    /// Below this a contact is noise rather than a finger.
    static let noiseSize = 0.05
    /// A feather-light tap: the quietest hit.
    static let softSize = 0.08
    /// The softest hit still sounds.
    static let minimumStrength = 0.12

    /// Fingers seen so far, with the frames they've been down, their size and place.
    private var fingers: [Int32: (frames: Int, size: Double, x: Double, y: Double)] = [:]
    /// The size of a full-force hit; grows if a finger lands harder still.
    private var hardSize = 0.9

    public init() {}

    /// Returns a hit for every finger on its second frame down, and for a
    /// tap so quick it lifted after a single frame.
    public mutating func update(contacts: [Contact]) -> [Hit] {
        var hits: [Hit] = []
        var next: [Int32: (frames: Int, size: Double, x: Double, y: Double)] = [:]
        for contact in contacts {
            var finger = fingers[contact.id] ?? (0, 0, contact.x, contact.y)
            finger.frames += 1
            finger.size = max(finger.size, contact.size)
            next[contact.id] = finger
            if finger.frames == 2 && finger.size >= Self.noiseSize {
                hits.append(Hit(x: finger.x, y: finger.y, strength: strength(for: finger.size)))
            }
        }
        for (id, finger) in fingers where next[id] == nil && finger.frames == 1 && finger.size >= Self.noiseSize {
            hits.append(Hit(x: finger.x, y: finger.y, strength: strength(for: finger.size)))
        }
        fingers = next
        return hits
    }

    /// 0…1 for a contact of this size, early in its touchdown.
    public mutating func strength(for size: Double) -> Double {
        hardSize = max(hardSize, size)
        let linear = ((size - Self.softSize) / (hardSize - Self.softSize)).clamped(to: 0...1)
        return Self.minimumStrength + (1 - Self.minimumStrength) * linear
    }

    public mutating func reset() {
        fingers.removeAll()
    }
}
