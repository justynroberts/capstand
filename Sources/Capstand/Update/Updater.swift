import AppKit
import Foundation

struct UpdateInfo: Equatable {
    let version: String
    /// The release page, for the browser.
    let url: URL
    /// The disk image, for the in-app installer. Nil if the release has none.
    let downloadURL: URL?
    let downloadSize: Int?
}

/// Checks GitHub for a newer release on launch and every few hours, offers it
/// once per version, and installs it on request. Installing never happens
/// unprompted: swapping the app mid-recording would drop the screen.
///
/// The only thing that leaves the machine is one request for the latest
/// release — no identifier, no device details.
@MainActor
final class Updater {

    nonisolated static let endpoint = URL(string: "https://api.github.com/repos/justynroberts/capstand/releases/latest")!
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let offeredKey = "offeredUpdateVersion"

    enum Status: Equatable {
        case idle, checking, upToDate, failed
        case installing(String)
    }

    private(set) var available: UpdateInfo?
    private(set) var status: Status = .idle
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var task: Task<Void, Never>?

    func start() {
        check(userInitiated: false)
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(userInitiated: false) }
        }
    }

    func check(userInitiated: Bool) {
        if case .installing = status { return }
        task?.cancel()
        set(.checking)
        task = Task { [weak self] in
            do {
                let info = try await Self.fetchLatest()
                guard let self else { return }
                let newer = Self.isNewer(info.version, than: Bundle.main.appVersion)
                self.available = newer ? info : nil
                self.set(newer ? .idle : .upToDate)
                if newer { self.offer(info, force: userInitiated) }
                else if userInitiated { Self.say("Capstand is up to date", "You have version \(Bundle.main.appVersion).") }
            } catch is CancellationError {
            } catch {
                NSLog("[capstand] update check failed: \(error)")
                self?.set(.failed)
                if userInitiated { Self.say("Could not check for updates", error.localizedDescription) }
            }
        }
    }

    /// Asks once per version, unless the user went looking.
    private func offer(_ info: UpdateInfo, force: Bool) {
        let defaults = UserDefaults.standard
        guard force || defaults.string(forKey: Self.offeredKey) != info.version else { return }
        defaults.set(info.version, forKey: Self.offeredKey)

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Capstand \(info.version) is available"
        alert.informativeText = "You have \(Bundle.main.appVersion). Capstand will restart to update — any phone window closes briefly."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { install() }
    }

    func install() {
        guard let info = available else { return }
        set(.installing("Downloading…"))
        Task {
            do {
                try await UpdateInstaller.install(info) { [weak self] step in self?.set(.installing(step)) }
            } catch {
                NSLog("[capstand] update failed: \(error)")
                set(.failed)
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = "Capstand could not update itself"
                alert.informativeText = "\(error.localizedDescription)\n\nYou can download it from the release page instead."
                alert.addButton(withTitle: "Open Release Page")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(info.url) }
            }
        }
    }

    private func set(_ status: Status) {
        self.status = status
        onChange?()
    }

    private static func say(_ title: String, _ detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    enum UpdateError: Error { case badResponse }

    nonisolated static func fetchLatest() async throws -> UpdateInfo {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = json["html_url"] as? String,
              let url = URL(string: page)
        else { throw UpdateError.badResponse }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        return UpdateInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                          url: url,
                          downloadURL: (dmg?["browser_download_url"] as? String).flatMap(URL.init),
                          downloadSize: dmg?["size"] as? Int)
    }

    /// Numeric, component-wise. "dev" parses to zero, so any release is newer.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
