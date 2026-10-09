import Foundation
import CoreGraphics

public final class IdleMonitor: @unchecked Sendable {
    public static let shared = IdleMonitor()

    private let anyInputEventType = CGEventType(rawValue: UInt32.max)!

    public func currentIdleSeconds() -> Double {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: anyInputEventType
        )
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return seconds
    }

    public func isUserIdle(timeoutSeconds: Double = 120.0) -> Bool {
        return currentIdleSeconds() >= timeoutSeconds
    }
}
