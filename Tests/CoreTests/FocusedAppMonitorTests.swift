import XCTest
@testable import avgFlow

@MainActor
final class FocusedAppMonitorTests: XCTestCase {
    func testPollingDetectsFrontmostAppChangeWhenNotificationIsMissed() {
        var snapshot = FocusedAppMonitor.AppSnapshot(
            pid: 101,
            bundleID: "com.example.first",
            name: "First"
        )
        let monitor = FocusedAppMonitor {
            snapshot
        }

        var changes: [(pid: pid_t, bundleID: String?, name: String?)] = []
        monitor.onAppChanged = { pid, bundleID, name in
            changes.append((pid, bundleID, name))
        }

        monitor.start()
        snapshot = FocusedAppMonitor.AppSnapshot(
            pid: 202,
            bundleID: "com.example.second",
            name: "Second"
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        monitor.stop()

        XCTAssertEqual(changes.map(\.pid), [101, 202])
        XCTAssertEqual(changes.last?.bundleID, "com.example.second")
    }
}
