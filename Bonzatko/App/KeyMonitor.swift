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
///
/// SwiftUI may call `onAppear` of a rebuilt view before `onDisappear` of the old one (e.g. when the
/// "Opravit výsledky" panel is toggled), so starts and stops are counted instead of simply replacing each other.
@MainActor
final class KeyMonitor {
    private var token: Any?
    private var activeCount = 0
    private var handler: (@MainActor (DrawKey, NSWindow?) -> Bool)?

    var isActive: Bool { token != nil }

    func start(_ handler: @escaping @MainActor (DrawKey, NSWindow?) -> Bool) {
        self.handler = handler
        activeCount += 1
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Leave keys alone while a sheet (e.g. renaming) is open or a text field is being edited.
            guard let key = DrawKey(event: event) else { return event }
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                guard let window = NSApp.window(withWindowNumber: windowNumber), window.attachedSheet == nil,
                      !(window.firstResponder is NSTextView) else {
                    return false
                }
                return self?.handler?(key, window) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        activeCount = max(activeCount - 1, 0)
        guard activeCount == 0, let token else { return }
        NSEvent.removeMonitor(token)
        self.token = nil
        handler = nil
    }
}
