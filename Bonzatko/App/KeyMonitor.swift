import AppKit

/// Keys of the drawing screen.
enum DrawKey: Equatable {
    case space, up, down, left, right, undo, fullScreen

    /// Maps a key event; `nil` for keys the drawing screen does not use.
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "z" {
            self = .undo
            return
        }
        guard modifiers.isEmpty else { return nil }
        switch event.keyCode {
        case 49: self = .space
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 51: self = .undo // Backspace
        default:
            guard event.charactersIgnoringModifiers?.lowercased() == "f" else { return nil }
            self = .fullScreen
        }
    }
}

/// Listens to key presses in the main window while the drawing screen is shown.
/// A local monitor works regardless of which control has focus, so keys work right after the app is activated.
@MainActor
final class KeyMonitor {
    private var token: Any?

    func start(_ handler: @escaping @MainActor (DrawKey, NSWindow?) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Leave keys alone while a sheet (e.g. renaming) is open or a text field is being edited.
            guard let key = DrawKey(event: event) else { return event }
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                guard let window = NSApp.window(withWindowNumber: windowNumber), window.attachedSheet == nil,
                      !(window.firstResponder is NSTextView) else {
                    return false
                }
                return handler(key, window)
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
    }
}
