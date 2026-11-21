import ActivityKit
import Foundation
import UIKit

/// 잠금화면·다이내믹 아일랜드의 '다음 일정' 카드.
/// iOS는 앱이 화면에 있을 때만 새 라이브 액티비티를 시작하게 해서, 앱을 열거나 일정이 바뀔 때 갱신한다.
/// 시작 시각이 지나면 카드가 "잘 마무리했어?"로 바뀌고, 답할 때까지(최대 3시간) 그대로 둔다.
enum LiveActivityManager {
    /// 이 시간 안에 시작하는 일정만 띄운다
    static let window: TimeInterval = 3 * 3600
    /// 끝난 뒤 마무리 체크를 기다려 주는 시간
    static let checkWindow: TimeInterval = 3 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// force: 3시간 제한 없이 24시간 안 다음 일정을 바로 띄운다(설정의 '지금 띄워보기')
    static func refresh(store: Store, force: Bool = false) {
        let settings = store.settings
        let now = Date()
        var next = store.upNext(now: now)
        // '못 했어'로 연장한 일정이 있으면 그걸 먼저
        if let e = settings.extended, e.until > now, let item = store.items.first(where: { $0.id == e.itemID }) {
            next = (item: item, when: e.until)
        }
        Task { await apply(next: next, settings: settings, force: force) }
    }

    static func apply(next: (item: ScheduleItem, when: Date)?, settings: AppSettings, force: Bool) async {
        let current = Activity<NextUpAttributes>.activities
        let now = Date()
        guard settings.liveActivity, isAvailable else {
            for a in current { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        // 아직 답하지 않은 마무리 체크가 있으면 그대로 둔다
        if !force, let pending = current.first(where: { a in
            let s = a.content.state
            return s.result == nil && s.start <= now && now.timeIntervalSince(s.start) < checkWindow
                && ResultLog.result(s.itemID, s.start) == nil
        }) {
            for a in current where a.id != pending.id { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let limit = force ? 86400 : window
        guard let next, next.when.timeIntervalSinceNow <= limit else {
            for a in current where a.content.state.result == nil { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        var state = makeState(next.item, next.when, settings: settings)
        if let same = current.first(where: { $0.content.state.itemID == state.itemID && $0.content.state.start == state.start }) {
            state.from = min(state.from, same.content.state.from)
            await same.update(ActivityContent(state: state, staleDate: next.when))
            for a in current where a.id != same.id { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        for a in current { await a.end(nil, dismissalPolicy: .immediate) }
        _ = try? Activity.request(attributes: NextUpAttributes(),
                                  content: ActivityContent(state: state, staleDate: next.when),
                                  pushType: nil)
    }

    static func makeState(_ x: ScheduleItem, _ when: Date, settings: AppSettings) -> NextUpAttributes.ContentState {
        let timeLabel: String
        if x.kind == .timetable {
            timeLabel = x.time + " – " + (x.end % 1440 == 0 && x.end > 0 ? "24:00" : Day.clock(x.end))
        } else {
            timeLabel = x.time
        }
        // 연장한 일정은 연장된 시각을 보여준다
        let minuteOfDay = Day.cal.component(.hour, from: when) * 60 + Day.cal.component(.minute, from: when)
        let shownTime = minuteOfDay == x.start % 1440 ? timeLabel : Day.clock(minuteOfDay) + "까지 (연장)"
        let minutesLeft = max(Int((when.timeIntervalSinceNow / 60).rounded(.up)), 1)
        let line = settings.effectiveTone == .plain ? nil : Nag.line(settings: settings, item: x, minutesBefore: minutesLeft)
        let avatarURL = Store.activeAvatarURL(settings)
        return NextUpAttributes.ContentState(
            itemID: x.id,
            title: x.title,
            place: x.place,
            kindLabel: x.kind == .timetable ? "시간표" : "약속",
            timeLabel: shownTime,
            colorHex: Palette.hex[min(max(x.color, 0), Palette.hex.count - 1)],
            from: min(Date(), when.addingTimeInterval(-window)),
            start: when,
            sender: Nag.sender(settings: settings),
            line: line,
            avatar: avatarURL.flatMap { AvatarImage.thumbnail(from: $0) },
            avatarKey: avatarURL.flatMap { shareAvatar($0, personID: settings.activePersonID ?? "x") },
            result: nil)
    }

    /// 고화질 사진을 공유 폴더에 복사하고 파일 키를 돌려준다(이미 있으면 그대로)
    static func shareAvatar(_ src: URL, personID: String) -> String? {
        guard let dir = SharedBox.container else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: src.path))?[.modificationDate] as? Date
        let key = "\(personID)-\(Int(modified?.timeIntervalSince1970 ?? 0))"
        guard let dest = NextUpAttributes.avatarFile(key) else { return nil }
        if FileManager.default.fileExists(atPath: dest.path) { return key }
        // 옛 사진 정리
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for f in files where f.hasPrefix("avatar-") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        }
        guard let data = try? Data(contentsOf: src),
              let image = UIImage(data: data),
              let jpeg = AvatarImage.resized(image, side: 240).jpegData(compressionQuality: 0.9) else { return nil }
        do { try jpeg.write(to: dest, options: .atomic) } catch { return nil }
        return key
    }
}
