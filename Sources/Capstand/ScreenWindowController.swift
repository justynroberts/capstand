import AppKit
import AVFoundation

/// One window per connected phone: a capture session feeding a chromeless,
/// aspect-locked, resizable window, plus the phone's audio on the Mac's output.
final class ScreenWindowController: NSWindowController, NSWindowDelegate {

    let device: AVCaptureDevice

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.fintonlabs.capstand.session")
    private let screenView = ScreenView()
    private var input: AVCaptureDeviceInput?
    private let audio = AVCaptureAudioPreviewOutput()
    /// The latest show/hide request. A fade-out that finishes after a newer
    /// show must not order the window out.
    private var wantsVisible = false
    private var observers: [NSObjectProtocol] = []
    /// A modern iPhone in portrait, until the stream reports its real size.
    private var videoSize = CGSize(width: 1179, height: 2556)
    /// Stream plus frame. Sizing works in its canvas, not the bare stream.
    private var frameLayout: FrameLayout

    private var frameName: String { "screen-\(device.uniqueID)" }

    var isShowing: Bool { wantsVisible }

    init(device: AVCaptureDevice, contextMenu: NSMenu) {
        self.device = device
        self.frameLayout = FrameRenderer.layout(for: Settings.frameStyle, video: videoSize, island: Settings.dynamicIsland)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 780),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = device.localizedName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 120, height: 120)

        super.init(window: window)

        window.delegate = self
        window.contentView = screenView
        screenView.menu = contextMenu

        configureSession()
        applySettings()

        if window.setFrameUsingName(frameName) {
            matchAspect(animate: false)
        } else {
            window.center()
            resize(toScreenFraction: 0.6, animate: false)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Capture

    private func configureSession() {
        session.beginConfiguration()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                self.input = input
            }
        } catch {
            NSLog("[capstand] could not open \(device.localizedName): \(error)")
        }
        // Without this the phone's sound goes nowhere: capture mutes the phone.
        audio.volume = 1
        if session.canAddOutput(audio) { session.addOutput(audio) }
        session.commitConfiguration()

        screenView.previewLayer.session = session

        let center = NotificationCenter.default
        // Fires when the stream starts and whenever the phone rotates.
        observers.append(center.addObserver(forName: AVCaptureInput.Port.formatDescriptionDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let self, let port = note.object as? AVCaptureInput.Port, port.input === self.input else { return }
            self.refreshVideoSize()
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                            object: session, queue: .main) { note in
            NSLog("[capstand] session error: \(String(describing: note.userInfo?[AVCaptureSessionErrorKey]))")
        })
    }

    private func refreshVideoSize() {
        let port = input?.ports.first { $0.mediaType == .video }
        guard let description = port?.formatDescription else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(description)
        let size = CGSize(width: Int(dims.width), height: Int(dims.height))
        guard size.width > 0, size.height > 0, size != videoSize else { return }
        NSLog("[capstand] \(device.localizedName) streaming \(Int(size.width))×\(Int(size.height))")
        videoSize = size
        refreshFrame(animate: true)
    }

    // MARK: - Showing

    func show() {
        guard let window else { return }
        wantsVisible = true
        audio.volume = 1
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        if !window.isVisible { window.alphaValue = 0 }
        // Never steals focus from whatever is being recorded alongside it.
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    /// Hiding keeps the capture running, muted, so showing again is instant —
    /// restarting an iPhone capture session takes a second or two.
    /// `stopCapture` is for when the window is going away for good.
    func hide(stopCapture: Bool = false, then completion: (() -> Void)? = nil) {
        guard let window else { return }
        wantsVisible = false
        audio.volume = 0
        if stopCapture {
            sessionQueue.async { [session] in session.stopRunning() }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.wantsVisible == false {
                window.orderOut(nil)
                window.alphaValue = 1
            }
            completion?()
        })
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func applySettings() {
        guard let window else { return }
        window.level = Settings.stacking.level
        window.hasShadow = Settings.shadow
        screenView.finish = Settings.finish
        refreshFrame(animate: true)
    }

    /// Rebuilds the frame for the current style and stream shape, and re-fits
    /// the window to it.
    private func refreshFrame(animate: Bool) {
        frameLayout = FrameRenderer.layout(for: Settings.frameStyle, video: videoSize, island: Settings.dynamicIsland)
        screenView.frameLayout = frameLayout
        matchAspect(animate: animate)
    }

    // MARK: - Sizing

    func windowDidMove(_ notification: Notification) { window?.saveFrame(usingName: frameName) }
    func windowDidEndLiveResize(_ notification: Notification) { window?.saveFrame(usingName: frameName) }

    /// Fits the window inside `fraction` of the screen's usable area.
    func resize(toScreenFraction fraction: CGFloat, animate: Bool = true) {
        guard let visible = visibleFrame else { return }
        let canvas = frameLayout.canvas
        let scale = min(visible.width * fraction / canvas.width, visible.height * fraction / canvas.height)
        place(scale: scale, animate: animate)
    }

    /// One stream pixel per screen pixel on the phone's screen, capped to what fits.
    func resizeToActualPixels() {
        let pixelsPerUnit = videoSize.width / frameLayout.screen.width
        place(scale: pixelsPerUnit / (window?.backingScaleFactor ?? 2), animate: true)
    }

    /// Re-shapes to the canvas's aspect ratio, keeping the long edge — so a
    /// rotated phone gives a window of the same visual size, turned.
    private func matchAspect(animate: Bool) {
        guard let window else { return }
        let canvas = frameLayout.canvas
        let longEdge = max(window.frame.width, window.frame.height)
        place(scale: longEdge / max(canvas.width, canvas.height), animate: animate)
    }

    private var visibleFrame: NSRect? {
        (window?.screen ?? NSScreen.main)?.visibleFrame
    }

    private func place(scale: CGFloat, animate: Bool) {
        guard let window, let visible = visibleFrame else { return }
        let canvas = frameLayout.canvas
        window.contentAspectRatio = canvas
        let fit = min(scale, visible.width / canvas.width, visible.height / canvas.height)
        let size = NSSize(width: (canvas.width * fit).rounded(), height: (canvas.height * fit).rounded())
        var frame = NSRect(x: window.frame.midX - size.width / 2, y: window.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
        window.saveFrame(usingName: frameName)
    }
}
