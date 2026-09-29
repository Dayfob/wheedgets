/// Tracks which keys are held, to recognize auto-repeat.
///
/// The system's auto-repeat flag on key events is not reliable enough on its
/// own, so a key-down for a key that is already down counts as a repeat.
public struct PressedKeys: Sendable {
    private var down: Set<UInt16> = []

    public init() {}

    /// Records the event and returns true when it is a repeat of a held key.
    public mutating func register(keyCode: UInt16, isDown: Bool) -> Bool {
        if isDown {
            return !down.insert(keyCode).inserted
        }
        down.remove(keyCode)
        return false
    }

    /// Forget everything, e.g. when the tap stops and key-ups may be missed.
    public mutating func reset() {
        down.removeAll()
    }
}
