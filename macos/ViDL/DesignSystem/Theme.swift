import SwiftUI

enum Theme {
    static let accent = Color(red: 0.55, green: 0.32, blue: 0.96)
    static let accentSecondary = Color(red: 0.93, green: 0.28, blue: 0.60)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let danger = Color(red: 0.95, green: 0.34, blue: 0.40)

    static let bgTop = Color(red: 0.09, green: 0.09, blue: 0.13)
    static let bgBottom = Color(red: 0.03, green: 0.03, blue: 0.06)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var successGradient: LinearGradient {
        LinearGradient(colors: [success, Color(red: 0.10, green: 0.62, blue: 0.42)],
                       startPoint: .leading, endPoint: .trailing)
    }

    static var appBackground: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.18), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [accentSecondary.opacity(0.12), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
