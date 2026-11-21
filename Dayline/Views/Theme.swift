import SwiftUI
import UIKit

// 토스 결 + 라벤더. 밝은/어두운 화면 모두 대응하는 색.

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(red: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255,
                  alpha: alpha)
    }

    func mixed(with other: UIColor, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount,
                       green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount,
                       alpha: a1)
    }
}

extension Color {
    static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

enum Theme {
    static let bg = Color.dynamic("FFFFFF", "101114")
    /// 화면 바탕(카드 뒤) / 카드
    static let screen = Color.dynamic("F2F4F6", "121317")
    static let card = Color.dynamic("FFFFFF", "1D1E24")
    /// 섹션 사이 두꺼운 띠, 회색 바탕
    static let band = Color.dynamic("F2F4F6", "1A1B1F")
    static let text = Color.dynamic("191F28", "F2F3F5")
    static let sub = Color.dynamic("6B7684", "A3A9B3")
    static let faint = Color.dynamic("8B95A1", "8B919B")
    static let line = Color.dynamic("F2F4F6", "24262B")
    static let accent = Color.dynamic("7B5CE6", "9D85F2")
    static let accentStrong = Color.dynamic("5B3FC4", "C9BBFF")
    static let accentSoft = Color.dynamic("F1ECFF", "2B2547")
    static let pill = Color.dynamic("F2F4F6", "2A2C32")
    static let pillText = Color.dynamic("4E5968", "C9CCD3")
    static let tabIdle = Color.dynamic("B0B8C1", "6B707B")
    static let tabBar = Color.dynamic("FFFFFF", "17181C")
}

extension Palette {
    private static func base(_ i: Int) -> UIColor { UIColor(hex: hex[min(max(i, 0), hex.count - 1)]) }

    /// 블록·아이콘 배경 (연한 색)
    static func soft(_ i: Int) -> Color {
        let c = base(i)
        return Color(uiColor: UIColor { t in c.withAlphaComponent(t.userInterfaceStyle == .dark ? 0.28 : 0.15) })
    }

    /// 불투명한 연한 색 (시간표 블록). 카드 색 위에 섞은 것과 같은 색
    static func solid(_ i: Int) -> Color {
        let c = base(i)
        return Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? c.mixed(with: UIColor(hex: "1D1E24"), 0.66) : c.mixed(with: .white, 0.8)
        })
    }

    /// 연한 배경 위 글씨 (진한 색)
    static func strong(_ i: Int) -> Color {
        let c = base(i)
        return Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? c.mixed(with: .white, 0.4) : c.mixed(with: .black, 0.35)
        })
    }
}

// MARK: - 시간 표현

enum TimeText {
    /// "23분 뒤", "2시간 5분 뒤", "1일 뒤"
    static func until(_ when: Date, from now: Date) -> String {
        let m = Int((when.timeIntervalSince(now) / 60).rounded(.up))
        if m <= 0 { return "지금" }
        if m < 60 { return "\(m)분 뒤" }
        if m < 1440 { return m % 60 == 0 ? "\(m / 60)시간 뒤" : "\(m / 60)시간 \(m % 60)분 뒤" }
        return "\(m / 1440)일 뒤"
    }

    /// "오후 6:30"
    static func ampm(_ hhmm: String) -> String {
        Day.format(Day.time(fromMinutes: Day.minutes(hhmm)), "ahmm")
    }

    /// "6:30"
    static func short(_ hhmm: String) -> String {
        let m = Day.minutes(hhmm)
        let h = (m / 60) % 12 == 0 ? 12 : (m / 60) % 12
        return String(format: "%d:%02d", h, m % 60)
    }
}
