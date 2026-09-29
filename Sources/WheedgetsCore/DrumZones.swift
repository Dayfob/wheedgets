import Foundation

/// How the trackpad is divided into drums.
public enum DrumZoneLayout: String, Codable, CaseIterable, Sendable {
    case grid
    /// Zones drawn by tracing them on the trackpad.
    case custom
}

/// A point in the trackpad's normalized coordinates: 0…1, y pointing up.
public struct ZonePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A drum zone of any shape, traced on the trackpad.
public struct CustomZone: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Closed outline; the last point joins the first.
    public var outline: [ZonePoint]
    public var sound: SoundSource

    public init(id: UUID = UUID(), outline: [ZonePoint], sound: SoundSource) {
        self.id = id
        self.outline = outline
        self.sound = sound
    }

    /// Even-odd ray casting, so any simple outline works, concave included.
    public func contains(_ point: ZonePoint) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let a = outline[i], b = outline[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Area in trackpad units (the whole pad is 1).
    public var area: Double {
        guard outline.count >= 3 else { return 0 }
        var sum = 0.0
        var j = outline.count - 1
        for i in outline.indices {
            sum += (outline[j].x + outline[i].x) * (outline[j].y - outline[i].y)
            j = i
        }
        return abs(sum) / 2
    }

    /// The point labels go at: the outline's center of mass.
    public var center: ZonePoint {
        let n = Double(max(outline.count, 1))
        return ZonePoint(x: outline.map(\.x).reduce(0, +) / n, y: outline.map(\.y).reduce(0, +) / n)
    }
}

public enum ZoneTracing {
    /// Smaller than this (about 2% of the pad) is a slip, not a zone.
    public static let minimumArea = 0.02

    /// Turns a finger's path into a zone outline: drops jitter, keeps the
    /// shape's corners, and rejects scribbles too small or too thin to hit.
    public static func outline(from path: [ZonePoint]) -> [ZonePoint]? {
        let clamped = path.map { ZonePoint(x: $0.x.clamped(to: 0...1), y: $0.y.clamped(to: 0...1)) }
        let simplified = simplify(clamped, tolerance: 0.006)
        guard simplified.count >= 3 else { return nil }
        let zone = CustomZone(outline: simplified, sound: .builtin(.kick))
        return zone.area >= minimumArea ? simplified : nil
    }

    /// Ramer–Douglas–Peucker.
    static func simplify(_ points: [ZonePoint], tolerance: Double) -> [ZonePoint] {
        guard points.count > 2 else { return points }
        let first = points[0], last = points[points.count - 1]
        var farthest = 0, distance = 0.0
        for index in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[index], from: first, to: last)
            if d > distance { distance = d; farthest = index }
        }
        guard distance > tolerance else { return [first, last] }
        let left = simplify(Array(points[...farthest]), tolerance: tolerance)
        let right = simplify(Array(points[farthest...]), tolerance: tolerance)
        return left.dropLast() + right
    }

    private static func perpendicularDistance(_ p: ZonePoint, from a: ZonePoint, to b: ZonePoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
    }
}

extension DrumTrackpadSettings {
    /// The custom zone under a point; later zones sit on top of earlier ones.
    public func customZoneIndex(at point: ZonePoint) -> Int? {
        customZones.indices.last { customZones[$0].contains(point) }
    }
}
