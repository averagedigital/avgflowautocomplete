import ApplicationServices
import Foundation

final class AccessibilityObserver {
    static let applicationNotificationNames = [
        kAXFocusedUIElementChangedNotification as String
    ]
    static let textElementNotificationNames = [
        kAXValueChangedNotification as String,
        kAXSelectedTextChangedNotification as String
    ]

    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var observedApplication: AXUIElement?
    private var observedTextElement: AXUIElement?

    var onTextChanged: (() -> Void)?
    var onFocusChanged: (() -> Void)?

    // MARK: - Lifecycle

    func observe(pid: pid_t) {
        stopObserving()
        observedPID = pid

        var observer: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer else {
            observedPID = 0
            return
        }
        self.axObserver = observer

        let appElement = AXUIElementCreateApplication(pid)
        observedApplication = appElement

        for notification in Self.applicationNotificationNames {
            AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                refcon
            )
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    func observeTextChanges(on element: AXUIElement) {
        guard let observer = axObserver else { return }
        if let observedTextElement, CFEqual(observedTextElement, element) {
            return
        }

        stopObservingTextChanges()
        self.observedTextElement = element
        for notification in Self.textElementNotificationNames {
            AXObserverAddNotification(
                observer,
                element,
                notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    func stopObservingTextChanges() {
        guard let element = observedTextElement else { return }
        if let observer = axObserver {
            for notification in Self.textElementNotificationNames {
                AXObserverRemoveNotification(observer, element, notification as CFString)
            }
        }
        observedTextElement = nil
    }

    func stopObserving() {
        stopObservingTextChanges()
        guard let observer = axObserver else {
            observedApplication = nil
            observedPID = 0
            return
        }
        if let observedApplication {
            for notification in Self.applicationNotificationNames {
                AXObserverRemoveNotification(observer, observedApplication, notification as CFString)
            }
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        axObserver = nil
        observedApplication = nil
        observedPID = 0
    }

    deinit {
        stopObserving()
    }

    // MARK: - Internal (called from C callback)

    fileprivate func handleNotification(_ name: String) {
        let focusNotification = kAXFocusedUIElementChangedNotification as String
        if name == focusNotification {
            onFocusChanged?()
        } else {
            onTextChanged?()
        }
    }
}

// C-function callback required by AXObserverCreate
private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let instance = Unmanaged<AccessibilityObserver>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    instance.handleNotification(name)
}
