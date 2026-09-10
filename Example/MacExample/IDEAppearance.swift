import SwiftUI

/// Shared design tokens for the MacExample shell.
/// VARIANCE 7 · MOTION 4 · DENSITY 7
enum IDEAppearance {
    enum Spacing {
        static let xs = 4.0
        static let sm = 8.0
        static let md = 12.0
        static let lg = 16.0
        static let railWidth = 48.0
        static let sidebarWidth = 240.0
        static let tabHeight = 35.0
        static let statusBarHeight = 22.0
    }

    enum Radius {
        static let control = 6.0
    }

    enum ColorToken {
        static let workbench = Color(hex: 0x1e1e1e)
        static let activityRail = Color(hex: 0x333333)
        static let sidebar = Color(hex: 0x252526)
        static let editor = Color(hex: 0x1e1e1e)
        static let tabBar = Color(hex: 0x2d2d2d)
        static let tabActive = Color(hex: 0x1e1e1e)
        static let tabInactive = Color(hex: 0x2d2d2d)
        static let tabHover = Color(hex: 0x323232)
        static let statusBar = Color(hex: 0x007acc)
        static let border = Color(hex: 0x3c3c3c)
        static let accent = Color(hex: 0x007acc)
        static let foreground = Color(hex: 0xcccccc)
        static let muted = Color(hex: 0x858585)
        static let sidebarHeading = Color(hex: 0xbbbbbb)
        static let selection = Color(hex: 0x094771)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
