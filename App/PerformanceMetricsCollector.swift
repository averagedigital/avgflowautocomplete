import Foundation
import os

#if canImport(MetricKit)
import MetricKit

final class PerformanceMetricsCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = PerformanceMetricsCollector()

    private let logger = Logger(subsystem: "com.aicomplete.mac", category: "MetricKit")
    private var isStarted = false

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
    }

    func stop() {
        guard isStarted else { return }
        MXMetricManager.shared.remove(self)
        isStarted = false
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        logger.info("MetricKit received \(payloads.count, privacy: .public) metric payload(s)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        logger.error("MetricKit received \(payloads.count, privacy: .public) diagnostic payload(s)")
    }
}

#else

final class PerformanceMetricsCollector {
    static let shared = PerformanceMetricsCollector()

    func start() {}
    func stop() {}
}

#endif
