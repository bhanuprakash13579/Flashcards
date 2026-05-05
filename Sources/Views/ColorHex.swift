import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .blue
            return
        }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >>  8) & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }
}

enum DeckPalette {
    static let colors: [String] = [
        "#4F8EF7", "#F76C6C", "#7BC47F", "#F7B84F",
        "#A77DFF", "#3FB8AF", "#FF7AB6", "#5C6BC0",
        "#FF9F43", "#00D2D3", "#1DD1A1", "#C8D6E5",
        "#FD7272", "#9B59B6", "#2ECC71", "#E17055"
    ]
    static func random() -> String { colors.randomElement() ?? "#4F8EF7" }
}

extension Color {
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
