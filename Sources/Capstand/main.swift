import AppKit

// MIT License - Copyright (c) fintonlabs.com

let arguments = CommandLine.arguments

if arguments.contains("--version") {
    print(Bundle.main.appVersion)
    exit(0)
}

// Diagnostic: lists every external capture device the way the app sees them.
if arguments.contains("--list-devices") {
    DeviceWatcher.printDevices()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
