import UIKit

/// Centralises all haptic feedback. One call, correct semantics.
enum HapticService {
    static func correct() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func wrong() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    static func match() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func mismatch() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    static func tap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
