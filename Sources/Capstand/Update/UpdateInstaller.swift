import AppKit
import Foundation
import Security

/// Downloads a release disk image, checks it is signed by the same Developer
/// ID team as the running app, swaps it over the running bundle and relaunches.
/// Ported from Murmur, where this path is proven.
@MainActor
enum UpdateInstaller {

    enum InstallError: LocalizedError {
        case noDownload, badDownload, mountFailed, noAppInImage, unsigned(String), teamMismatch(String, String), swapFailed(String)
        var errorDescription: String? {
            switch self {
            case .noDownload: return "This release has no disk image to download."
            case .badDownload: return "The download did not complete."
            case .mountFailed: return "The disk image could not be opened."
            case .noAppInImage: return "The disk image does not contain Capstand."
            case .unsigned(let why): return "Signature validation failed: \(why)"
            case .teamMismatch(let a, let b): return "The download is signed by \(b), not \(a). Not installing it."
            case .swapFailed(let why): return "Could not replace the app: \(why)"
            }
        }
    }

    static func install(_ update: UpdateInfo, progress: @escaping @MainActor (String) -> Void) async throws {
        guard let downloadURL = update.downloadURL else { throw InstallError.noDownload }

        // Before downloading anything: a local dev build has no team, so it
        // could never accept a release over itself.
        let mine = try teamIdentifier(of: Bundle.main.bundleURL)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("capstand-update-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dmg = tmp.appendingPathComponent(downloadURL.lastPathComponent)

        progress("Downloading…")
        try await download(downloadURL, to: dmg, expected: update.downloadSize)

        progress("Verifying…")
        let mount = try attach(dmg)
        defer { detach(mount); try? FileManager.default.removeItem(at: tmp) }

        let contents = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else { throw InstallError.noAppInImage }
        let theirs = try teamIdentifier(of: newApp)
        guard mine == theirs else { throw InstallError.teamMismatch(mine, theirs) }

        progress("Installing…")
        let current = Bundle.main.bundleURL
        try swap(newApp, over: current)

        progress("Restarting…")
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
        try sh.run()
        NSApp.terminate(nil)
    }

    private static func download(_ url: URL, to file: URL, expected: Int?) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (location, response) = try await session.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError.badDownload }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: location, to: file)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if let expected, size != expected { throw InstallError.badDownload }
    }

    private static func attach(_ dmg: URL) throws -> URL {
        let out = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", "-plist", dmg.path])
        guard let plist = try? PropertyListSerialization.propertyList(from: out, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw InstallError.mountFailed }
        return URL(fileURLWithPath: mount, isDirectory: true)
    }

    private static func detach(_ mount: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
    }

    /// Validates the signature and returns the Team ID. Ad-hoc builds throw.
    static func teamIdentifier(of bundle: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            throw InstallError.unsigned("not a signed bundle")
        }
        var error: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil, &error) == errSecSuccess else {
            throw InstallError.unsigned(error?.takeRetainedValue().localizedDescription ?? "invalid")
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        else { throw InstallError.unsigned("no Team ID — this is a local build") }
        return team
    }

    /// Copy in beside the current bundle, then two renames. The running
    /// process keeps its mapped pages until it relaunches.
    private static func swap(_ newApp: URL, over current: URL) throws {
        let fm = FileManager.default
        let parent = current.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(current.lastPathComponent + ".update")
        let old = parent.appendingPathComponent(current.lastPathComponent + ".previous")
        try? fm.removeItem(at: staged); try? fm.removeItem(at: old)

        // ditto keeps the signature and the stapled ticket intact.
        _ = try run("/usr/bin/ditto", [newApp.path, staged.path])
        do {
            try fm.moveItem(at: current, to: old)
        } catch {
            try? fm.removeItem(at: staged)
            throw InstallError.swapFailed(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: staged, to: current)
        } catch {
            try? fm.moveItem(at: old, to: current)
            throw InstallError.swapFailed(error.localizedDescription)
        }
        try? fm.removeItem(at: old)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw InstallError.swapFailed("\(URL(fileURLWithPath: tool).lastPathComponent) exited \(p.terminationStatus)")
        }
        return data
    }
}
