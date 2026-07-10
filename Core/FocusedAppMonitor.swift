import AppKit
import ApplicationServices

@MainActor
final class FocusedAppMonitor {
    struct AppSnapshot: Equatable {
        let pid: pid_t
        let bundleID: String?
        let name: String?
    }

    private(set) var currentAppPID: pid_t = 0
    private(set) var currentAppBundleID: String?
    private(set) var currentAppName: String?
    private(set) var currentAppElement: AXUIElement?

    var onAppChanged: ((pid_t, String?, String?) -> Void)?

    private let frontmostAppSnapshot: () -> AppSnapshot?
    private var observer: NSObjectProtocol?
    private var pollingTimer: Timer?

    init(frontmostAppSnapshot: @escaping () -> AppSnapshot? = FocusedAppMonitor.defaultFrontmostAppSnapshot) {
        self.frontmostAppSnapshot = frontmostAppSnapshot
    }

    func start() {
        updateFrontmostApp()

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFrontmostApp()
            }
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFrontmostApp()
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        currentAppPID = 0
        currentAppBundleID = nil
        currentAppName = nil
        currentAppElement = nil
    }

    @discardableResult
    private func updateFrontmostApp() -> Bool {
        guard let snapshot = frontmostAppSnapshot() else {
            return false
        }
        let pid = snapshot.pid
        guard pid != currentAppPID else {
            return false
        }
        currentAppPID = pid
        currentAppBundleID = snapshot.bundleID
        currentAppName = snapshot.name
        currentAppElement = AXUIElementCreateApplication(pid)
        onAppChanged?(pid, snapshot.bundleID, snapshot.name)
        return true
    }

    private static func defaultFrontmostAppSnapshot() -> AppSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return AppSnapshot(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            name: app.localizedName
        )
    }
}
