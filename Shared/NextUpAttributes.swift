import ActivityKit
import SwiftUI

/// 앱과 위젯 확장이 함께 쓰는 라이브 액티비티 데이터.
/// 앱이 다음 일정 정보를 넘겨주고, 카운트다운은 iOS가 알아서 줄여준다.
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
        /// 나만의 말투의 보낸 사람 이름
        var sender: String?
        /// 잔소리 한 줄
        var line: String?
        /// 프로필 사진 썸네일(JPEG, 2~3KB). 라이브 액티비티 데이터는 4KB 제한이라 아주 작게.
        var avatar: Data?
        /// 공유 폴더(App Group)의 고화질 사진 파일 이름 "avatar-<key>.jpg"
        var avatarKey: String?
        /// "done"이면 '했어'를 누른 뒤
        var result: String?
        /// 보낸 사람 색 (카드·다이내믹 아일랜드). nil이면 기본 라벤더
        var accentHex: String?
        /// 다른 프로필이 끼어든 한 줄 (가끔)
        var cameoName: String?
        var cameoLine: String?
        var cameoHex: String?
        var cameoAvatarKey: String?
    }

    /// 고화질 프로필 사진 (공유 폴더)
    static func avatarFile(_ key: String) -> URL? { SharedBox.file("avatar-\(key).jpg") }

    static func color(_ hex: String) -> Color {
        let v = UInt64(hex, radix: 16) ?? 0x6c8ee8
        return Color(red: Double((v >> 16) & 0xff) / 255,
                     green: Double((v >> 8) & 0xff) / 255,
                     blue: Double(v & 0xff) / 255)
    }
}
