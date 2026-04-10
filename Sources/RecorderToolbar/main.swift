import AppKit

let app = NSApplication.shared
// main.swift runs on the main thread; assumeIsolated is safe here
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
