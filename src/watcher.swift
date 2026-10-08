// Turns the TV on when the Mac or its display wakes, and off on lock, display sleep or system sleep.
import AppKit
import CoreGraphics

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
var lastOn = Date.distantPast
var lastOff = Date.distantPast

func tvctl(_ cmd: String, _ reason: String, wait: Bool = false) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    p.arguments = ["-I", dir + "/tvctl.py", cmd, reason]
    try? p.run()
    if wait { p.waitUntilExit() }
}

// One wake fires several events, so debounce.
func on(_ reason: String) {
    guard Date().timeIntervalSince(lastOn) > 8 else { return }
    lastOn = Date()
    tvctl("on", reason)
}

func off(_ reason: String, wait: Bool = false) {
    guard Date().timeIntervalSince(lastOff) > 8 else { return }
    lastOff = Date()
    tvctl("off", reason, wait: wait)
}

let ws = NSWorkspace.shared.notificationCenter
for (name, reason) in [
    (NSWorkspace.didWakeNotification, "system wake"),
    (NSWorkspace.screensDidWakeNotification, "screen wake"),
    (NSWorkspace.sessionDidBecomeActiveNotification, "session active"),
] {
    ws.addObserver(forName: name, object: nil, queue: .main) { _ in on(reason) }
}
// Escape at the lock screen and idle dimming both arrive as screen sleep.
ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
    off("screen sleep")
}
ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
    off("system sleep", wait: true)
}

let dnc = DistributedNotificationCenter.default()
for (name, reason) in [
    ("com.apple.screenIsUnlocked", "unlocked"),
    ("com.apple.screensaver.didstop", "screensaver stopped"),
] {
    dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in on(reason) }
}
// On lock, turn the TV off and sleep the display, so a key press at the
// lock screen counts as a screen wake and turns the TV back on.
dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    off("locked")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["displaysleepnow"]
    try? p.run()
}

// External display reappearing (clamshell wake). Ignored right after turning the TV off.
CGDisplayRegisterReconfigurationCallback({ display, flags, _ in
    if flags.contains(.addFlag) || (flags.contains(.enabledFlag) && CGDisplayIsBuiltin(display) == 0) {
        DispatchQueue.main.async {
            if Date().timeIntervalSince(lastOff) > 15 { on("display connected") }
        }
    }
}, nil)

NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
