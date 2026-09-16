import AppKit

enum Stacking: String, CaseIterable {
    case front, normal, back

    var title: String {
        switch self {
        case .front: return "Always on Top"
        case .normal: return "Normal"
        case .back: return "Behind Other Windows"
        }
    }

    var level: NSWindow.Level {
        switch self {
        case .front: return .floating
        case .normal: return .normal
        // Just above the desktop icons, below every app window.
        case .back: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }
}

/// How the screen is presented. FrameRenderer turns each into a FrameLayout.
enum FrameStyle: String, CaseIterable {
    case none, rounded, iphone, bundled, custom

    /// `.bundled` has no single title; the menu lists each shipped frame.
    var title: String {
        switch self {
        case .none: return "None"
        case .rounded: return "Rounded Corners"
        case .iphone: return "iPhone"
        case .bundled: return "Classic iPhone"
        case .custom: return "Custom Image"
        }
    }
}

/// Colour of the drawn iPhone frame's titanium rail and buttons.
enum Finish: String, CaseIterable {
    case black, natural, white, desert

    var title: String { "\(rawValue.capitalized) Titanium" }

    var base: NSColor {
        switch self {
        case .black: return NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
        case .natural: return NSColor(srgbRed: 0.66, green: 0.64, blue: 0.60, alpha: 1)
        case .white: return NSColor(srgbRed: 0.85, green: 0.85, blue: 0.82, alpha: 1)
        case .desert: return NSColor(srgbRed: 0.70, green: 0.60, blue: 0.52, alpha: 1)
        }
    }

    var highlight: NSColor { base.blended(withFraction: 0.45, of: .white) ?? base }
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    var title: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var stacking: Stacking {
        get { defaults.string(forKey: "stacking").flatMap(Stacking.init) ?? .front }
        set { defaults.set(newValue.rawValue, forKey: "stacking") }
    }

    static var frameStyle: FrameStyle {
        get { defaults.string(forKey: "frameStyle").flatMap(FrameStyle.init) ?? .iphone }
        set { defaults.set(newValue.rawValue, forKey: "frameStyle") }
    }

    /// Which shipped frame `.bundled` shows, by file name.
    static var bundledFrame: String? {
        get { defaults.string(forKey: "bundledFrame") }
        set { defaults.set(newValue, forKey: "bundledFrame") }
    }

    static var finish: Finish {
        get { defaults.string(forKey: "finish").flatMap(Finish.init) ?? .natural }
        set { defaults.set(newValue.rawValue, forKey: "finish") }
    }

    static var dynamicIsland: Bool {
        get { defaults.object(forKey: "dynamicIsland") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dynamicIsland") }
    }

    static var shadow: Bool {
        get { defaults.object(forKey: "shadow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shadow") }
    }

    static var appearance: Appearance {
        get { defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }
}

extension Bundle {
    /// "dev" for the bare SwiftPM binary, which has no Info.plist.
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
