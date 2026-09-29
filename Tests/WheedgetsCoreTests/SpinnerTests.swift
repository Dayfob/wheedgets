import Carbon.HIToolbox
import Foundation
import Testing
@testable import WheedgetsCore

struct SpinnerPhysicsTests {
    private func run(_ physics: inout SpinnerPhysics, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { physics.step(1.0 / 120) }
    }

    @Test func aFlickSpinsThenCoastsToRest() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1)
        #expect(physics.velocity == SpinnerPhysics.flick)

        run(&physics, seconds: 1)
        #expect(physics.velocity > 0 && physics.velocity < SpinnerPhysics.flick)

        run(&physics, seconds: 60)
        #expect(physics.velocity == 0)
        #expect(physics.isResting)
    }

    @Test func aFastSpinLastsLongerThanASlowOne() {
        func secondsToRest(from speed: Double) -> Double {
            var physics = SpinnerPhysics()
            physics.flick(direction: 1, strength: speed)
            var t = 0.0
            while physics.velocity > 0 && t < 600 { physics.step(0.01); t += 0.01 }
            return t
        }
        #expect(secondsToRest(from: 30) > secondsToRest(from: 5) * 2)
        #expect(secondsToRest(from: 30) > 20, "a hard spin whirs for a while")
    }

    @Test func holdingSpinKeepsAcceleratingUpToTheLimit() {
        var physics = SpinnerPhysics()
        physics.pushDirection = 1
        run(&physics, seconds: 2)
        #expect(physics.velocity > 10)
        run(&physics, seconds: 30)
        #expect(physics.velocity == SpinnerPhysics.maxSpeed)
    }

    @Test func brakingStopsMuchSoonerThanCoasting() {
        var coasting = SpinnerPhysics(), braking = SpinnerPhysics()
        coasting.flick(direction: 1, strength: 20)
        braking.flick(direction: 1, strength: 20)
        braking.isBraking = true
        run(&coasting, seconds: 3)
        run(&braking, seconds: 3)
        #expect(braking.velocity == 0)
        #expect(coasting.velocity > 15)
    }

    @Test func stopSettlesWithinASecond() {
        var physics = SpinnerPhysics()
        physics.flick(direction: -1, strength: SpinnerPhysics.maxSpeed)
        physics.stop()
        run(&physics, seconds: 1)
        #expect(physics.velocity == 0)
        #expect(!physics.isStopping)
    }

    @Test func spinContinuesInTheCurrentDirection() {
        var physics = SpinnerPhysics()
        #expect(physics.currentDirection == 1)
        physics.flick(direction: -1)
        #expect(physics.currentDirection == -1)
    }

    @Test func angleStaysWithinOneTurn() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: SpinnerPhysics.maxSpeed)
        run(&physics, seconds: 3)
        #expect(abs(physics.angle) < 1)
    }
}

struct SpinnerSoundTests {
    private func loudness(at speed: Double) -> Float {
        var sound = SpinnerSound(sampleRate: 48_000)
        var buffer = [Float](repeating: 0, count: 48_000)
        buffer.withUnsafeMutableBufferPointer { sound.render(into: $0.baseAddress!, count: $0.count, speed: speed) }
        // Skip the first half: the speed glides in.
        let tail = buffer[24_000...]
        return sqrt(tail.reduce(0) { $0 + $1 * $1 } / Float(tail.count))
    }

    @Test func atRestItSkipsTheWorkEntirely() {
        var sound = SpinnerSound(sampleRate: 48_000)
        var buffer = [Float](repeating: 42, count: 512)
        let audible = buffer.withUnsafeMutableBufferPointer { sound.renderIfAudible(into: $0.baseAddress!, count: 512, speed: 0) }
        #expect(!audible)
        #expect(buffer.allSatisfy { $0 == 42 }, "untouched: the caller marks the buffer silent")
        let spinning = buffer.withUnsafeMutableBufferPointer { sound.renderIfAudible(into: $0.baseAddress!, count: 512, speed: 10) }
        #expect(spinning)
    }

    @Test func silentAtRestLouderWhenFaster() {
        #expect(loudness(at: 0) < 0.001)
        #expect(loudness(at: 20) > loudness(at: 3))
        #expect(loudness(at: SpinnerPhysics.maxSpeed) < 1, "stays in range at top speed")
    }
}

struct SpinnerSettingsTests {
    @Test func defaultBindingsAreUnique() {
        let keys = SpinnerBinding.makeDefaults().map(\.keyCode)
        #expect(Set(keys).count == keys.count)
    }

    @Test func assigningATakenKeySwaps() {
        var settings = SpinnerSettings()
        let spin = settings.bindings[0], brake = settings.bindings[3]
        settings.assignKey(brake.keyCode, toBinding: spin.id)
        #expect(settings.bindings[0].keyCode == brake.keyCode)
        #expect(settings.bindings[3].keyCode == spin.keyCode)
    }

    @Test func clampsOutOfRangeValues() throws {
        let json = #"{"size": 9999, "spinTime": 0, "color": "rainbow"}"#
        let settings = try JSONDecoder().decode(SpinnerSettings.self, from: Data(json.utf8))
        #expect(settings.size == SpinnerSettings.sizeRange.upperBound)
        #expect(settings.spinTime == SpinnerSettings.spinTimeRange.lowerBound)
        #expect(settings.color == .cosmicOrange, "unknown colors (like an old palette's) fall back to the default")
    }
}

struct SpinnerKeyRoleTests {
    @Test func bindingsWinThenBrakeKeysThenNudges() {
        var settings = SpinnerSettings()
        let space = UInt16(kVK_Space), backspace = UInt16(kVK_Delete), letter = UInt16(kVK_ANSI_A)
        #expect(settings.role(of: space) == .action(.spin))
        #expect(settings.role(of: letter) == .none, "typing does nothing unless enabled")

        settings.spinsOnAnyKey = true
        #expect(settings.role(of: space) == .action(.spin))
        #expect(settings.role(of: backspace) == .typingBrake)
        #expect(settings.role(of: letter) == .typingNudge)
    }

    @Test func brakeKeysCanBeAddedOnceAndNeverEscape() {
        var settings = SpinnerSettings()
        settings.addTypingBrakeKey(UInt16(kVK_ForwardDelete))
        settings.addTypingBrakeKey(UInt16(kVK_ForwardDelete))
        settings.addTypingBrakeKey(KeyCodes.escape)
        #expect(settings.typingBrakeKeys == [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)])
    }
}

struct SpinnerSlowingTests {
    @Test func slowingNeverReversesTheSpin() {
        var physics = SpinnerPhysics()
        physics.flick(direction: -1, strength: 2)
        physics.slow(by: 1.5)
        #expect(abs(physics.velocity - -0.5) < 1e-9)
        physics.slow(by: 1.5)
        #expect(physics.velocity == 0)
    }

    @Test func equalStrengthsPushAndBrakeAlike() {
        // Held push adds speed as fast as held braking takes it away
        // (on top of the bearing's own friction, measured by coasting).
        var pushing = SpinnerPhysics(), braking = SpinnerPhysics(), coasting = SpinnerPhysics()
        pushing.pushDirection = 1
        braking.flick(direction: 1, strength: 20)
        coasting.flick(direction: 1, strength: 20)
        braking.isBraking = true
        for _ in 0..<60 { pushing.step(1.0 / 60); braking.step(1.0 / 60); coasting.step(1.0 / 60) }
        let brakeLoss = coasting.velocity - braking.velocity
        #expect(abs(pushing.velocity - brakeLoss) < 0.3)
    }

    @Test func strongerBrakeSlowsFaster() {
        var normal = SpinnerPhysics(), strong = SpinnerPhysics()
        strong.brakeStrength = 2
        normal.flick(direction: 1, strength: 20); strong.flick(direction: 1, strength: 20)
        normal.isBraking = true; strong.isBraking = true
        for _ in 0..<60 { normal.step(1.0 / 60); strong.step(1.0 / 60) }
        #expect(strong.velocity < normal.velocity - 5)
    }

    @Test func strongerPushAcceleratesFaster() {
        var normal = SpinnerPhysics(), strong = SpinnerPhysics()
        strong.pushStrength = 2
        normal.pushDirection = 1
        strong.pushDirection = 1
        for _ in 0..<60 { normal.step(1.0 / 60); strong.step(1.0 / 60) }
        #expect(strong.velocity > normal.velocity * 1.8)
    }
}

struct TrackpadDriveTests {
    /// A finger sweeping from (x, y0) to (x, y1) over `seconds`, at 100 frames/s.
    private func sweep(x: Double, from y0: Double, to y1: Double, seconds: Double = 0.2) -> Double? {
        var drive = TrackpadDrive()
        let frames = Int(seconds * 100)
        for frame in 0...frames {
            let t = Double(frame) / 100
            drive.update(contacts: [.init(id: 1, x: x, y: y0 + (y1 - y0) * t / seconds)], timestamp: t)
        }
        return drive.target
    }

    @Test func swipingUpRightOfCenterTurnsCounterclockwise() throws {
        #expect(try #require(sweep(x: 0.85, from: 0.3, to: 0.7)) < -0.3)
    }

    @Test func swipingUpLeftOfCenterTurnsClockwise() throws {
        #expect(try #require(sweep(x: 0.15, from: 0.3, to: 0.7)) > 0.3)
    }

    /// Circling at a given pace turns the spinner at that pace times the calibration.
    @Test(arguments: [0.5, 1.0, 2.0])
    func circlingSpeedFollowsTheFinger(lapsPerSecond: Double) throws {
        var drive = TrackpadDrive()
        let radius = 0.3
        for frame in 0...150 {
            let t = Double(frame) / 100
            // Clockwise on the pad, circle corrected for the pad's aspect.
            let angle = -2 * .pi * lapsPerSecond * t
            drive.update(
                contacts: [.init(id: 1, x: 0.5 + radius * cos(angle) / 1.5, y: 0.5 + radius * sin(angle))],
                timestamp: t
            )
        }
        let target = try #require(drive.target)
        let expected = lapsPerSecond * TrackpadDrive.calibration
        #expect(abs(target - expected) < expected * 0.05, "clockwise laps → clockwise spin, proportional")
    }

    @Test func fasterSwipesSpinFaster() throws {
        let slow = try #require(sweep(x: 0.15, from: 0.3, to: 0.7, seconds: 0.5))
        let fast = try #require(sweep(x: 0.15, from: 0.3, to: 0.7, seconds: 0.1))
        #expect(fast > slow * 2)
    }

    @Test func aRestingFingerDoesNothing() {
        var drive = TrackpadDrive()
        for frame in 0..<20 {
            drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.5)], timestamp: Double(frame) / 100)
        }
        #expect(drive.target == nil)
    }

    @Test func theFirstMomentsOfATouchAreAFlick() {
        var drive = TrackpadDrive()
        drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.3)], timestamp: 0)
        drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.35)], timestamp: 0.1)
        #expect(drive.isFlicking)
        drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.5)], timestamp: 0.5)
        #expect(!drive.isFlicking, "still down and moving: a drag")
    }

    @Test func aRestingFingerGripsOnlyAfterAMoment() {
        var drive = TrackpadDrive()
        var holds: [Double] = []
        for frame in 0...100 {
            drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.5)], timestamp: Double(frame) / 100)
            holds.append(drive.holdStrength)
        }
        #expect(holds[15] == 0, "a brief pause at the start of a gesture doesn't brake")
        #expect(holds[45] > 0 && holds[45] < 1, "grip builds up")
        #expect(holds[100] == 1)
    }

    @Test func aFingerThatLandsAndStaysPutGrabs() {
        var drive = TrackpadDrive()
        for frame in 0...3 {
            drive.update(contacts: [.init(id: 1, x: 0.7 + 0.001 * Double(frame), y: 0.5)], timestamp: Double(frame) / 100)
        }
        #expect(!drive.isGrabbing, "undecided in the first milliseconds")
        for frame in 4...10 {
            drive.update(contacts: [.init(id: 1, x: 0.7, y: 0.5)], timestamp: Double(frame) / 100)
        }
        #expect(drive.isGrabbing)
    }

    @Test func aFingerThatLandsMovingIsAGesture() {
        var drive = TrackpadDrive()
        for frame in 0...10 {
            drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.3 + 0.01 * Double(frame))], timestamp: Double(frame) / 100)
        }
        #expect(!drive.isGrabbing)
        #expect(drive.target != nil)
    }

    @Test func aGrabEndsWhenTheFingerMoves() {
        var drive = TrackpadDrive()
        for frame in 0...10 {
            drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.3)], timestamp: Double(frame) / 100)
        }
        #expect(drive.isGrabbing)
        for frame in 11...20 {
            drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.3 + 0.01 * Double(frame - 10))], timestamp: Double(frame) / 100)
        }
        #expect(!drive.isGrabbing)
    }

    @Test func movingOrLiftingReleasesTheGrip() {
        var drive = TrackpadDrive()
        for frame in 0...80 {
            drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.5)], timestamp: Double(frame) / 100)
        }
        #expect(drive.holdStrength > 0)
        drive.update(contacts: [], timestamp: 0.81)
        #expect(drive.holdStrength == 0)
    }

    @Test func liftingFingersEndsTheDrive() {
        var drive = TrackpadDrive()
        drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.3)], timestamp: 0)
        drive.update(contacts: [.init(id: 1, x: 0.8, y: 0.4)], timestamp: 0.01)
        #expect(drive.target != nil)
        drive.update(contacts: [], timestamp: 0.02)
        #expect(drive.target == nil)
    }
}

struct SpinnerFingerTests {
    private func run(_ physics: inout SpinnerPhysics, finger: Double?, flicking: Bool, frames: Int) -> [Double] {
        var speeds: [Double] = []
        for _ in 0..<frames {
            physics.setFinger(speed: finger, flicking: flicking)
            physics.step(1.0 / 120)
            speeds.append(physics.velocity)
        }
        return speeds
    }

    @Test func aFlickAlongTheSpinPushesItFasterWithoutSlowingIt() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: 10)
        let speeds = run(&physics, finger: 2, flicking: true, frames: 36)
        #expect(speeds.last! > 11.5, "10 rev/s plus a 2 rev/s flick")
        #expect(speeds.allSatisfy { $0 >= 9.95 }, "never dips on the way")
    }

    @Test func aFlickAgainstTheSpinThrowsItTheOtherWay() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: 10)
        let speeds = run(&physics, finger: -6, flicking: true, frames: 60)
        let jumps = zip(speeds, speeds.dropFirst()).map { abs($1 - $0) }
        #expect(jumps.max()! < 2, "smooth, never flips instantly")
        #expect(speeds.contains { abs($0) < 1 }, "passes through zero")
        #expect(abs(speeds.last! - -6) < 1, "ends at the flick's speed, reversed")
    }

    @Test func evenAWeakFlickAgainstAFastSpinReversesIt() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: 20)
        _ = run(&physics, finger: -2, flicking: true, frames: 36)
        #expect(physics.velocity < 0, "reversed, not merely slowed to 18")
    }

    @Test func aDragHoldsItAtTheFingerSpeed() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: 20)
        _ = run(&physics, finger: 2, flicking: false, frames: 120)
        #expect(abs(physics.velocity - 2) < 0.2)
    }

    @Test func aHoldingFingerStopsIt() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: 20)
        physics.touchHold = 1
        for _ in 0..<(120 * 2) { physics.step(1.0 / 120) }
        #expect(physics.velocity == 0)
    }

    @Test func aGrabStopsItAlmostAtOnceButSmoothly() {
        var physics = SpinnerPhysics()
        physics.flick(direction: 1, strength: 30)
        physics.isGrabbed = true
        var speeds: [Double] = []
        for _ in 0..<24 { physics.step(1.0 / 120); speeds.append(physics.velocity) }
        #expect(speeds.last! == 0, "stopped within 0.2 s")
        #expect(speeds[0] > 20, "not a one-frame jump")
    }

    @Test func aStrongerTouchBrakeStopsSooner() {
        var normal = SpinnerPhysics(), strong = SpinnerPhysics()
        normal.flick(direction: 1, strength: 20); strong.flick(direction: 1, strength: 20)
        normal.touchHold = 1; strong.touchHold = 1
        strong.touchBrakeStrength = 2
        for _ in 0..<30 { normal.step(1.0 / 120); strong.step(1.0 / 120) }
        #expect(strong.velocity < normal.velocity * 0.8)
    }

    @Test func liftingTheFingerLetsItCoast() {
        var physics = SpinnerPhysics()
        _ = run(&physics, finger: 5, flicking: false, frames: 120)
        let released = physics.velocity
        _ = run(&physics, finger: nil, flicking: false, frames: 12)
        #expect(physics.velocity > released * 0.95)
        #expect(physics.fingerTarget == nil)
    }
}
