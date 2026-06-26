import AppKit
import ApplicationServices

@MainActor
final class FocusedAppMonitor {
    private(set) var currentAppPID: pid_t = 0
    private(set) var currentAppBundleID: String?
    private(set) var currentAppName: String?
    private(set) var currentAppElement: AXUIElement?

    var onAppChanged: ((pid_t, String?, String?) -> Void)?

    private var observer: NSObjectProtocol?

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
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        currentAppPID = 0
        currentAppBundleID = nil
        currentAppName = nil
        currentAppElement = nil
    }

    private func updateFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return
        }
        let pid = app.processIdentifier
        guard pid != currentAppPID else {
            return
        }
        currentAppPID = pid
        currentAppBundleID = app.bundleIdentifier
        currentAppName = app.localizedName
        currentAppElement = AXUIElementCreateApplication(pid)
        onAppChanged?(pid, app.bundleIdentifier, app.localizedName)
    }
}
