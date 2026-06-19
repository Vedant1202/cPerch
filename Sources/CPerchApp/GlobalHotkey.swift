import AppKit
import Carbon.HIToolbox

// ─────────────────────────────────────────────────────────────────────────────
// #9 · GlobalHotkey — one system-wide chord that toggles the bar popover.
//
// Registers a SINGLE global hotkey via Carbon's `RegisterEventHotKey` and fires a
// stored closure on each press. The default chord is ⌘⌥` (Command-Option-Backtick),
// wired up by MenuBarController to `togglePopover()`.
//
// WHY CARBON (and not NSEvent): a Carbon hotkey needs NO TCC permission. The OS
// owns the registration and only hands us the one chord we asked for — it never
// sees other keystrokes. The obvious AppKit alternative,
// `NSEvent.addGlobalMonitorForEvents`, taps the global keyboard stream and so
// requires the Input Monitoring permission (and Accessibility for some setups);
// both are outside this app's boundaries. RegisterEventHotKey is the deliberate,
// permission-free, fully-local choice.
//
// The chord is registered by physical key CODE (`kVK_ANSI_Grave`), not by the
// produced character, so it tracks the same top-left key across keyboard layouts
// rather than chasing where "`" happens to live.
//
// Carbon's C event-handler callback can't capture Swift context, so we hand it an
// opaque pointer to `self` as `userData` and recover the instance inside the
// callback. The press is bounced onto the main thread before invoking `onPress`,
// since it drives AppKit UI. A failed registration (e.g. the chord is already
// claimed by another app) returns nil so the caller degrades gracefully instead
// of trapping — losing the hotkey is never worth crashing the bar.
//
// Side-effecty AppKit/Carbon glue with no unit-test target (it needs a live event
// dispatcher and real key presses): the bar here is "compiles cleanly +
// structurally-correct Carbon interop". Verified by hand against a live build.
// ─────────────────────────────────────────────────────────────────────────────

/// Registers one global hotkey through Carbon and calls `onPress` when it fires.
/// Lives as long as it's retained; tears the registration down in `deinit`.
final class GlobalHotkey {
    private let onPress: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Register `keyCode` + `modifiers` as a system-wide hotkey.
    ///
    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `UInt32(kVK_ANSI_Grave)`.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(cmdKey | optionKey)`.
    ///   - onPress: invoked on the main thread each time the chord is pressed.
    /// - Returns: nil if either the event handler or the hotkey fails to register,
    ///   so a collision with another app degrades gracefully rather than trapping.
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress

        // 'cprh' (cPerch hotkey) as the signature; id 1 — we only register one chord.
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let target = GetEventDispatcherTarget()

        // The C callback gets an opaque pointer back to us via `userData`; it can't
        // close over Swift values. `passUnretained` is safe because the handler is
        // torn down in `deinit`, so it never outlives `self`.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            target,
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                // Hop to the main thread: `onPress` drives AppKit (popover/UI).
                DispatchQueue.main.async { me.onPress() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
        guard handlerStatus == noErr else { return nil }

        // `0` options; the dispatcher target receives the synthesized hot-key event.
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 target, 0, &hotKeyRef)
        guard registerStatus == noErr, hotKeyRef != nil else {
            // Roll back the handler we just installed so we don't leak it on failure.
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Four-char-code signature for our hotkey id: 'cprh'.
    private static let signature: OSType = {
        let chars = Array("cprh".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()
}
