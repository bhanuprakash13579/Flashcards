import SwiftUI

/// One source of truth for spacing, color semantics, and typography.
///
/// Design intent (cognitive-load oriented):
///   • Semantic colors only — no decorative palettes inside study screens.
///   • Tinted backgrounds at ~10% opacity instead of saturated fills (long sessions).
///   • Rounded display font for card faces — short reads, easier on the eye.
///   • One CTA per study screen.
enum Theme {

    // MARK: Semantic colors

    /// Affirmative: "Got it", success states, mastery.
    static let success: Color = .green

    /// Stretch / "Hard" / lapse — amber, *not* red, to avoid harsh judgement.
    static let stretch: Color = .orange

    /// Calm focus / "Easy" / streak — soft blue, satisfaction.
    static let focus: Color = .blue

    /// Destructive only (delete, irreversible).
    static let destructive: Color = .red

    /// Streak flame.
    static let streak: Color = .orange

    // MARK: Tinted surfaces

    /// 10% opacity tint — for state recognition without retina fatigue.
    static func surface(_ color: Color) -> Color { color.opacity(0.10) }

    /// 18% opacity tint — for buttons / pills.
    static func chip(_ color: Color) -> Color { color.opacity(0.18) }

    // MARK: Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 14
        static let l:  CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: Corners

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 18
    }

    // MARK: Typography

    /// Big card-face text — rounded, generous, balanced for active recall.
    static func cardFace(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    /// Section labels (ALL CAPS, tiny).
    static let label: Font = .caption2.weight(.bold)
}
