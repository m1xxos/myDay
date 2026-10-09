import Foundation
import SwiftUI

public extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        default:
            self.init(.gray)
        }
    }
}
