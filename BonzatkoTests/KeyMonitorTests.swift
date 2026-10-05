import AppKit
import Testing
@testable import Bonzatko

@MainActor
struct KeyMonitorTests {
    /// The rebuilt view appears before the old one disappears; keys must keep working.
    @Test func overlappingStartAndStopKeepsListening() {
        let monitor = KeyMonitor()
        monitor.start { _, _ in true }
        monitor.start { _, _ in true }
        monitor.stop()
        #expect(monitor.isActive)
        monitor.stop()
        #expect(!monitor.isActive)
    }

    @Test func mapsDrawingKeys() throws {
        func key(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags = []) -> DrawKey? {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                         windowNumber: 0, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            return event.flatMap(DrawKey.init(event:))
        }
        #expect(key(49, " ") == .space)
        #expect(key(126, "") == .up)
        #expect(key(125, "") == .down)
        #expect(key(123, "") == .left)
        #expect(key(124, "") == .right)
        #expect(key(51, "\u{7F}") == .undo)
        #expect(key(6, "z", .command) == .undo)
        #expect(key(3, "f") == .fullScreen)
        #expect(key(0, "a") == nil)
        #expect(key(3, "f", .command) == nil)
    }
}
