import ActivityKit
import SwiftUI

/// 앱과 위젯 확장이 함께 쓰는 라이브 액티비티 데이터.
/// 앱이 다음 일정 정보를 넘겨주고, 카운트다운은 iOS가 알아서 줄여준다(서버·App Group 불필요).
struct NextUpAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var itemID: String
        var title: String
        var place: String
        /// "시간표" / "약속"
        var kindLabel: String
        /// "14:00 – 15:15" 또는 "14:00"
        var timeLabel: String
        var colorHex: String
        /// 카운트다운 시작 시각(라이브 액티비티를 띄운 때)
        var from: Date
        /// 일정 시작 시각
        var start: Date
    }

    static func color(_ hex: String) -> Color {
        let v = UInt64(hex, radix: 16) ?? 0x6c8ee8
        return Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
}
