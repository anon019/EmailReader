import AppKit
import SwiftUI

enum ReaderTheme {
    static let paper = adaptive(light: 0xF7F4EC, dark: 0x151714)
    static let sidebar = adaptive(light: 0xECE9E0, dark: 0x10120F)
    static let queue = adaptive(light: 0xF2EFE7, dark: 0x181A16)
    static let reader = adaptive(light: 0xFCFBF7, dark: 0x1C1F1A)
    static let selected = adaptive(light: 0xE7DFD0, dark: 0x302C22)
    static let ink = adaptive(light: 0x242A25, dark: 0xEEF1EB)
    static let muted = adaptive(light: 0x6B726B, dark: 0xA5ADA5)
    static let faint = adaptive(light: 0xA4A9A2, dark: 0x737B74)
    static let divider = adaptive(light: 0xD6D1C7, dark: 0x343831)
    static let accent = adaptive(light: 0xA8651A, dark: 0xE3A152)
    static let positive = adaptive(light: 0x47705A, dark: 0x7EB293)

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
extension Font {
    static func editorial(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("New York", size: size).weight(weight)
    }

    static func chineseEditorial(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("STSongti-SC-Regular", size: size).weight(weight)
    }
}
