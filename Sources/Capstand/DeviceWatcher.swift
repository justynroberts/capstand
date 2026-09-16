import AVFoundation
import CoreMediaIO

/// Finds iPhone/iPad screens and reports them coming and going.
///
/// This is the same path QuickTime uses. macOS hides iOS screen devices from
/// capture apps until a process opts in through CoreMediaIO; after that the
/// phone appears as an ordinary external, muxed (video + audio) capture device
/// a second or two after it is plugged in. The phone must be unlocked and have
/// trusted this Mac.
final class DeviceWatcher {

    var onConnect: ((AVCaptureDevice) -> Void)?
    var onDisconnect: ((String) -> Void)?

    private var discovery: AVCaptureDevice.DiscoverySession?
    private var observation: NSKeyValueObservation?
    private var tokens: [NSObjectProtocol] = []
    private var connected: Set<String> = []

    func start() {
        Self.allowScreenCaptureDevices()
        // Created after the opt-in, or it never sees the phone.
        let discovery = Self.makeDiscovery()
        self.discovery = discovery

        observation = discovery.observe(\.devices, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.sync() }
        }
        // Belt and braces: the KVO path has been known to lag hot-plug events.
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sync()
            })
        }
    }

    private func sync() {
        guard let discovery else { return }
        let screens = discovery.devices.filter(Self.isIOSScreen)
        let ids = Set(screens.map(\.uniqueID))

        for gone in connected.subtracting(ids) {
            NSLog("[capstand] disconnected \(gone)")
            onDisconnect?(gone)
        }
        for device in screens where !connected.contains(device.uniqueID) {
            NSLog("[capstand] connected \(device.localizedName) (\(device.modelID))")
            onConnect?(device)
        }
        connected = ids
    }

    private static func isIOSScreen(_ device: AVCaptureDevice) -> Bool {
        device.hasMediaType(.muxed) && device.manufacturer.hasPrefix("Apple")
    }

    private static func makeDiscovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
    }

    static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
                                               UInt32(MemoryLayout<UInt32>.size), &allow)
        if status != 0 { NSLog("[capstand] enabling screen capture devices failed: \(status)") }
    }

    /// `Capstand --list-devices`. Waits a few seconds, because devices appear
    /// asynchronously after the opt-in.
    static func printDevices() {
        allowScreenCaptureDevices()
        let all = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: nil, position: .unspecified)
        var devices: [AVCaptureDevice] = []
        for _ in 0..<5 {
            devices = all.devices
            if devices.contains(where: isIOSScreen) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        if devices.isEmpty { print("No external capture devices. Is the phone plugged in, unlocked and trusted?") }
        for d in devices {
            print("\(isIOSScreen(d) ? "✓" : " ") \(d.localizedName) — model \(d.modelID), maker \(d.manufacturer), muxed \(d.hasMediaType(.muxed)), id \(d.uniqueID)")
        }
    }
}
