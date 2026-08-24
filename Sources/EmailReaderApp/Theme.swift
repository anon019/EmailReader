import AppKit
import SwiftUI

enum ReaderTheme {
    static let paper = adaptive(light: 0xF3F1EB, dark: 0x11130F)
    static let sidebar = adaptive(light: 0xE9E6DE, dark: 0x151712)
    static let queue = adaptive(light: 0xF0EEE8, dark: 0x181B16)
    static let reader = adaptive(light: 0xFAF9F5, dark: 0x1D201A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x252820)
    static let surfaceRaised = adaptive(light: 0xF8F5EE, dark: 0x2A2D24)
    static let selected = adaptive(light: 0xDED8CB, dark: 0x343126)
    static let selectedStrong = adaptive(light: 0xD5CBBB, dark: 0x40392B)
    static let ink = adaptive(light: 0x1F2520, dark: 0xF2F4EE)
    static let muted = adaptive(light: 0x626B63, dark: 0xB1B8AF)
    static let faint = adaptive(light: 0x8B928B, dark: 0x7D857C)
    static let divider = adaptive(light: 0xD2CEC4, dark: 0x383C34)
    static let accent = adaptive(light: 0xA95D24, dark: 0xF0A45F)
    static let accentSoft = adaptive(light: 0xF0DFCE, dark: 0x4A3222)
    static let positive = adaptive(light: 0x3F7358, dark: 0x83C19B)
    static let positiveSoft = adaptive(light: 0xDDEBE2, dark: 0x203A2D)
    static let danger = adaptive(light: 0xA6483D, dark: 0xF28B7E)
    static let dangerSoft = adaptive(light: 0xF0DCD8, dark: 0x452523)
    static let info = adaptive(light: 0x4B667F, dark: 0x8CB4D8)
    static let shadow = Color.black.opacity(0.10)

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
