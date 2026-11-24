import ActivityKit
import BackgroundTasks
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
        scheduleTick(start: next?.when)
    }

    // MARK: 30분마다 문구 바꾸기

    static let tickTaskID = "app.dayline.ios.tick"

    /// 남은 시간을 30분 단위로 내림 (30분 미만은 그대로). 이 값이 바뀌면 카드 문구를 새로 고른다.
    static func bucket(minutesLeft m: Int) -> Int { m >= 30 ? (m / 30) * 30 : m }

    /// 다음 '남은 시간이 30분의 배수'가 되는 시각
    static func nextBoundary(start: Date, now: Date = Date()) -> Date? {
        let left = start.timeIntervalSince(now)
        guard left > 30 * 60 else { return nil }
        let k = (left / 1800).rounded(.down)
        let t = start.addingTimeInterval(-k * 1800)
        return t > now.addingTimeInterval(5) ? t : start.addingTimeInterval(-(k - 1) * 1800)
    }

    /// 앱이 화면에 있을 때 호출: 카드 문구가 다음 30분 칸으로 넘어갔으면 카드만 갱신한다
    static func tickIfNeeded(store: Store) {
        guard let a = Activity<NextUpAttributes>.activities.first, a.content.state.result == nil else { return }
        let s = a.content.state
        guard s.start > Date() else { return }
        let m = max(Int((s.start.timeIntervalSinceNow / 60).rounded(.up)), 1)
        if lastBucket != bucket(minutesLeft: m) { refresh(store: store) }
    }
    private static var lastBucket: Int?

    /// 백그라운드에서도 다음 30분 경계에 깨워 달라고 요청 (iOS가 시각을 조금 늦출 수 있음)
    static func scheduleTick(start: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: tickTaskID)
        guard let start, let at = nextBoundary(start: start) else { return }
        let r = BGAppRefreshTaskRequest(identifier: tickTaskID)
        r.earliestBeginDate = at
        try? BGTaskScheduler.shared.submit(r)
    }

    static func registerTick() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: tickTaskID, using: nil) { task in
            Task { @MainActor in
                await CyberCampus.syncIfNeeded(store: Store.shared)
                await refreshNow(store: Store.shared)
                task.setTaskCompleted(success: true)
            }
        }
    }

    /// 백그라운드·단축어용: 끝날 때까지 기다리는 갱신. 띄우려던 다음 일정을 돌려준다.
    @MainActor
    @discardableResult
    static func refreshNow(store: Store) async -> (item: ScheduleItem, when: Date)? {
        let settings = store.settings
        var next = store.upNext(now: Date())
        if let e = settings.extended, e.until > Date(), let item = store.items.first(where: { $0.id == e.itemID }) {
            next = (item: item, when: e.until)
        }
        await apply(next: next, settings: settings, force: false)
        scheduleTick(start: next?.when)
        return next
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

        // 카드를 지웠다가 새로 띄울 때만 문구(와 끼어들기)를 새로 뽑는다
        rerollLine()
        state = makeState(next.item, next.when, settings: settings)
        for a in current { await a.end(nil, dismissalPolicy: .immediate) }
        _ = try? Activity.request(attributes: NextUpAttributes(),
                                  content: ActivityContent(state: state, staleDate: next.when),
                                  pushType: nil)
    }

    /// 카드를 새로 띄울 때마다 올라가는 번호. 카드 문구(와 끼어들기)를 새로 뽑는다.
    static var reroll: Int { UserDefaults.standard.integer(forKey: "cardReroll") }
    static func rerollLine() { UserDefaults.standard.set(reroll + 1, forKey: "cardReroll") }

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
        // 문구는 30분 칸마다 한 번씩 바뀐다 (2:17 남음 → '2시간' 문구, 2:00이 되면 다음 문구는 1:30에)
        let shown = bucket(minutesLeft: minutesLeft)
        lastBucket = shown
        let line = settings.effectiveTone == .plain ? nil : Nag.line(settings: settings, item: x, minutesBefore: shown, salt: "|r\(reroll)")
        let avatarURL = Store.activeAvatarURL(settings)
        // 메인 문구를 나눠 보내면 카드 자리가 없어서 끼어들기는 쉰다
        let extra = (line == nil || line!.contains("\n")) ? nil : cameo(for: x, bucket: shown, settings: settings)
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
            result: nil,
            accentHex: settings.activePerson?.colorHex,
            cameoName: extra?.name,
            cameoLine: extra?.line,
            cameoHex: extra?.hex,
            cameoAvatarKey: extra?.avatarKey)
    }

    /// 확률(약 35%)로 다른 프로필이 자기 말투로 한마디 끼어든다.
    /// 같은 일정·같은 30분 칸에서는 늘 같은 결과라 새로 고쳐도 깜빡이지 않는다.
    static let cameoChance: UInt64 = 35

    static func cameo(for x: ScheduleItem, bucket: Int, settings: AppSettings)
        -> (name: String, line: String, hex: String?, avatarKey: String?)? {
        let others = settings.people.filter { $0.id != settings.activePersonID }
        guard settings.activePerson != nil, !others.isEmpty else { return nil }
        let seed = "\(x.id)|\(bucket)|cameo|r\(reroll)"
        guard Nag.stableHash(seed) % 100 < cameoChance else { return nil }
        let other = others[Int(Nag.stableHash(seed + "|who") % UInt64(others.count))]
        var s = settings
        s.activePersonID = other.id
        guard s.effectiveTone != .plain else { return nil }
        let line = Nag.line(settings: s, item: x, minutesBefore: bucket, salt: "|cameo|r\(reroll)")
        let key = Store.activeAvatarURL(s).flatMap { shareAvatar($0, personID: other.id) }
        return (other.name, line, other.colorHex, key)
    }

    /// 고화질 사진을 공유 폴더에 복사하고 파일 키를 돌려준다(이미 있으면 그대로)
    static func shareAvatar(_ src: URL, personID: String) -> String? {
        guard let dir = SharedBox.container else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: src.path))?[.modificationDate] as? Date
        let key = "\(personID)-\(Int(modified?.timeIntervalSince1970 ?? 0))"
        guard let dest = NextUpAttributes.avatarFile(key) else { return nil }
        if FileManager.default.fileExists(atPath: dest.path) { return key }
        // 같은 사람의 옛 사진만 정리 (끼어드는 사람 사진은 남겨둔다)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for f in files where f.hasPrefix("avatar-\(personID)-") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        }
        guard let data = try? Data(contentsOf: src),
              let image = UIImage(data: data),
              let jpeg = AvatarImage.resized(image, side: 240).jpegData(compressionQuality: 0.9) else { return nil }
        do { try jpeg.write(to: dest, options: .atomic) } catch { return nil }
        return key
    }
}
