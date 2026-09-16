import AppKit
import AVFoundation
import ServiceManagement

/// Menu bar app: no Dock icon, one window per plugged-in phone. The status
/// menu and each window's right-click menu are the same menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let watcher = DeviceWatcher()
    private let updater = Updater()
    private var statusItem: NSStatusItem!
    private var controllers: [String: ScreenWindowController] = [:]
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = Settings.appearance.nsAppearance

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = makeMenu()
        updateStatusIcon()

        watcher.onConnect = { [weak self] device in self?.deviceConnected(device) }
        watcher.onDisconnect = { [weak self] id in self?.deviceDisconnected(id) }
        watcher.start()

        updater.mayInterrupt = { [weak self] in
            !(self?.controllers.values.contains { $0.isShowing } ?? false)
        }
        updater.start()

        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated { self?.toggleAllScreens() }
        }
    }

    // MARK: - Devices

    private func deviceConnected(_ device: AVCaptureDevice) {
        withCameraAccess { [weak self] granted in
            guard let self else { return }
            guard granted else { return self.explainCameraDenied() }
            guard self.controllers[device.uniqueID] == nil, device.isConnected else { return }
            let controller = ScreenWindowController(device: device, contextMenu: self.makeMenu())
            self.controllers[device.uniqueID] = controller
            controller.show()
            self.updateStatusIcon()
        }
    }

    private func deviceDisconnected(_ id: String) {
        guard let controller = controllers.removeValue(forKey: id) else { return }
        controller.hide(stopCapture: true) { controller.close() }
        updateStatusIcon()
    }

    private func withCameraAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            NSApp.activate()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    private func explainCameraDenied() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Capstand needs camera access"
        alert.informativeText = "macOS treats a plugged-in iPhone screen as a camera. Allow Capstand under Privacy & Security → Camera, then plug the phone in again."
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        }
    }

    private func updateStatusIcon() {
        let symbol = controllers.isEmpty ? "iphone.gen3" : "iphone.gen3.radiowaves.left.and.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Capstand")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }

    /// Rebuilt each time it opens, so it always reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if controllers.isEmpty {
            add(to: menu, "Plug in an iPhone to show its screen", nil).isEnabled = false
        } else {
            for controller in controllers.values.sorted(by: { $0.device.localizedName < $1.device.localizedName }) {
                add(to: menu, controller.device.localizedName, #selector(toggleScreen(_:)),
                    value: controller.device.uniqueID, on: controller.isShowing)
            }
        }

        if hotKey?.isRegistered == true {
            let toggle = add(to: menu, "Show/Hide Screen", #selector(toggleAllScreens), key: HotKey.keyEquivalent)
            toggle.keyEquivalentModifierMask = HotKey.modifierFlags
            toggle.isEnabled = !controllers.isEmpty
            toggle.toolTip = "\(HotKey.displayString) works from any app"
        } else {
            add(to: menu, "Show/Hide Screen", #selector(toggleAllScreens)).isEnabled = !controllers.isEmpty
            add(to: menu, "\(HotKey.displayString) is taken by another app", nil).isEnabled = false
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Window"))
        for stacking in Stacking.allCases {
            add(to: menu, stacking.title, #selector(setStacking(_:)), value: stacking.rawValue, on: Settings.stacking == stacking)
        }

        let size = submenu(in: menu, "Size")
        for (title, fraction) in [("Small", 0.4), ("Medium", 0.6), ("Large", 0.85), ("Fill Screen Height", 1.0)] {
            add(to: size, title, #selector(setSize(_:)), value: fraction)
        }
        add(to: size, "Actual Pixels", #selector(setSize(_:)), value: 0.0)

        let frame = submenu(in: menu, "Frame")
        for style in [FrameStyle.none, .rounded, .iphone] {
            add(to: frame, style.title, #selector(setFrameStyle(_:)), value: style.rawValue, on: Settings.frameStyle == style)
        }
        let current = ImageFrame.bundled(named: Settings.bundledFrame)?.name
        for bundled in ImageFrame.bundled {
            add(to: frame, bundled.title, #selector(setBundledFrame(_:)), value: bundled.name,
                on: Settings.frameStyle == .bundled && bundled.name == current)
        }
        add(to: frame, FrameStyle.custom.title, #selector(setFrameStyle(_:)), value: FrameStyle.custom.rawValue,
            on: Settings.frameStyle == .custom).isEnabled = ImageFrame.customExists
        frame.addItem(.separator())
        let isPhone = Settings.frameStyle == .iphone
        for finish in Finish.allCases {
            add(to: frame, finish.title, #selector(setFinish(_:)), value: finish.rawValue, on: Settings.finish == finish).isEnabled = isPhone
        }
        add(to: frame, "Dynamic Island", #selector(toggleIsland), on: Settings.dynamicIsland).isEnabled = isPhone
        frame.addItem(.separator())
        add(to: frame, "Choose Custom Image…", #selector(chooseCustomFrame))
        add(to: menu, "Shadow", #selector(toggleShadow), on: Settings.shadow)

        menu.addItem(.separator())
        let appearance = submenu(in: menu, "Appearance")
        for option in Appearance.allCases {
            add(to: appearance, option.title, #selector(setAppearance(_:)), value: option.rawValue, on: Settings.appearance == option)
        }
        add(to: menu, "Open at Login", #selector(toggleLoginItem), on: SMAppService.mainApp.status == .enabled)

        switch updater.status {
        case .installing(let step):
            add(to: menu, "Updating — \(step)", nil).isEnabled = false
        default:
            if let update = updater.available {
                add(to: menu, "Update to \(update.version)…", #selector(installUpdate))
            } else {
                add(to: menu, updater.status == .checking ? "Checking for Updates…" : "Check for Updates",
                    #selector(checkForUpdates)).isEnabled = updater.status != .checking
            }
        }

        menu.addItem(.separator())
        add(to: menu, "About Capstand", #selector(showAbout))
        add(to: menu, "Quit Capstand", #selector(NSApplication.terminate(_:)), key: "q").target = NSApp
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector?, key: String = "",
                     value: Any? = nil, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.representedObject = value
        item.state = on ? .on : .off
        menu.addItem(item)
        return item
    }

    private func submenu(in menu: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        sub.autoenablesItems = false
        item.submenu = sub
        menu.addItem(item)
        return sub
    }

    // MARK: - Actions

    @objc private func toggleScreen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let controller = controllers[id] else { return }
        controller.isShowing ? controller.hide() : controller.show()
    }

    /// The hotkey: if any phone window is showing, hide them all; otherwise show them all.
    @objc private func toggleAllScreens() {
        guard !controllers.isEmpty else { return NSSound.beep() }
        let anyShowing = controllers.values.contains { $0.isShowing }
        for controller in controllers.values {
            anyShowing ? controller.hide() : controller.show()
        }
    }

    @objc private func setStacking(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Stacking(rawValue: raw) else { return }
        Settings.stacking = value
        applySettings()
    }

    /// Applies to every phone window; there is usually just one.
    @objc private func setSize(_ sender: NSMenuItem) {
        guard let fraction = sender.representedObject as? Double else { return }
        for controller in controllers.values {
            fraction == 0 ? controller.resizeToActualPixels() : controller.resize(toScreenFraction: fraction)
        }
    }

    @objc private func setFrameStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = FrameStyle(rawValue: raw) else { return }
        Settings.frameStyle = value
        applySettings()
    }

    @objc private func toggleShadow() {
        Settings.shadow.toggle()
        applySettings()
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Appearance(rawValue: raw) else { return }
        Settings.appearance = value
        NSApp.appearance = value.nsAppearance
    }

    @objc private func setBundledFrame(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Settings.bundledFrame = name
        Settings.frameStyle = .bundled
        applySettings()
    }

    @objc private func setFinish(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Finish(rawValue: raw) else { return }
        Settings.finish = value
        applySettings()
    }

    @objc private func toggleIsland() {
        Settings.dynamicIsland.toggle()
        applySettings()
    }

    /// Any front-on phone PNG with a transparent or flat-colour screen works.
    @objc private func chooseCustomFrame() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.message = "Choose a front-on phone image (PNG) with a transparent or flat-colour screen"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageFrame.importImage(from: url)
            Settings.frameStyle = .custom
            applySettings()
        } catch {
            let alert = NSAlert()
            alert.messageText = "That image can't be used as a frame"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("[capstand] login item change failed: \(error)")
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    @objc private func checkForUpdates() { updater.check(userInitiated: true) }
    @objc private func installUpdate() { updater.install() }
    @objc private func showAbout() { AboutPanel.shared.present() }

    private func applySettings() {
        controllers.values.forEach { $0.applySettings() }
    }
}
