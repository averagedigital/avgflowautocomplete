import XCTest
@testable import avgFlow

final class PermissionsManagerTests: XCTestCase {
    func testPermissionDiagnosticsRowsSeparateUsedAndUnusedMacOSPermissions() {
        let rows = PermissionsManager.permissionRows(
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )

        XCTAssertEqual(
            rows,
            [
                PermissionDiagnosticsRow(
                    name: "Accessibility",
                    status: .required,
                    purpose: "Read focused text fields and selected text via AX."
                ),
                PermissionDiagnosticsRow(
                    name: "Input Monitoring",
                    status: .granted,
                    purpose: "Receive global accept/cancel hotkeys from the event tap."
                ),
                PermissionDiagnosticsRow(
                    name: "Automation",
                    status: .notUsed,
                    purpose: "Not used by this stack."
                ),
                PermissionDiagnosticsRow(
                    name: "Screen Recording",
                    status: .notUsed,
                    purpose: "Not used by this stack."
                )
            ]
        )
    }

    @MainActor
    func testInputMonitoringGrantPostsNotificationOnceOnTransition() {
        var isGranted = false
        let manager = PermissionsManager(inputMonitoringCheck: { isGranted })
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .inputMonitoringPermissionGranted,
            object: nil,
            queue: .main
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertFalse(manager.checkInputMonitoring())
        isGranted = true
        XCTAssertTrue(manager.checkInputMonitoring())
        XCTAssertTrue(manager.checkInputMonitoring())
        XCTAssertEqual(notificationCount, 1)
    }
}
