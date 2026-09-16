import AppKit
import CoreText

/// "Made by FintonLabs". Follows the app's light/dark choice through
/// semantic colours; Escape or the close button dismisses it.
final class AboutPanel: NSPanel {

    static let shared = AboutPanel()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 250),
                   styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        Fonts.register()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let name = NSTextField(labelWithString: "Capstand")
        name.font = Fonts.display(30, weight: .bold)

        let version = NSTextField(labelWithString: "Version \(Bundle.main.appVersion)")
        version.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        version.textColor = .secondaryLabelColor

        let blurb = NSTextField(wrappingLabelWithString: "Shows your iPhone's screen whenever it's plugged in, ready to record.")
        blurb.alignment = .center
        blurb.textColor = .secondaryLabelColor
        blurb.preferredMaxLayoutWidth = 240

        let link = NSButton(title: "Made by FintonLabs", target: self, action: #selector(openSite))
        link.bezelStyle = .push
        link.keyEquivalent = "\r"
        link.toolTip = "https://fintonlabs.com"

        let stack = NSStackView(views: [icon, name, version, blurb, link])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(16, after: blurb)
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 24, bottom: 20, right: 24)
        contentView = stack
    }

    @objc private func openSite() {
        NSWorkspace.shared.open(URL(string: "https://fintonlabs.com")!)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    func present() {
        center()
        alphaValue = 0
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            animator().alphaValue = 1
        }
    }
}

/// Bricolage Grotesque is not a system face; register the bundled copy.
/// Never through Bundle.module — see Package.swift.
enum Fonts {
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/BricolageGrotesque.ttf")
        let candidates = [Bundle.main.url(forResource: "BricolageGrotesque", withExtension: "ttf"), source]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            NSLog("[capstand] Bricolage not found — falling back to the system font")
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func display(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFontDescriptor(fontAttributes: [.family: "Bricolage Grotesque"])
            .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        return NSFont(descriptor: base, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
