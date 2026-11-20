import ActivityKit
import Foundation

/// 잠금화면·다이내믹 아일랜드의 '다음 일정' 카드.
/// iOS는 앱이 화면에 있을 때만 새 라이브 액티비티를 시작하게 해서, 앱을 열거나 일정이 바뀔 때 갱신한다.
enum LiveActivityManager {
    /// 이 시간 안에 시작하는 일정만 띄운다
    static let window: TimeInterval = 3 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// force: 3시간 제한 없이 24시간 안 다음 일정을 바로 띄운다(설정의 '지금 띄워보기')
    static func refresh(store: Store, force: Bool = false) {
        let settings = store.settings
        let next = store.upNext(now: Date())
        Task { await apply(next: next, settings: settings, force: force) }
    }

    static func apply(next: (item: ScheduleItem, when: Date)?, settings: AppSettings, force: Bool) async {
        let current = Activity<NextUpAttributes>.activities
        let limit = force ? 86400 : window
        guard settings.liveActivity, isAvailable, let next, next.when.timeIntervalSinceNow <= limit else {
            for a in current { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        var state = makeState(next.item, next.when)
        if let same = current.first(where: { $0.content.state.itemID == state.itemID && $0.content.state.start == state.start }) {
            state.from = same.content.state.from // 카운트다운이 처음부터 다시 시작하지 않게
            await same.update(ActivityContent(state: state, staleDate: next.when))
            for a in current where a.id != same.id { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }

        for a in current { await a.end(nil, dismissalPolicy: .immediate) }
        _ = try? Activity.request(attributes: NextUpAttributes(),
                                  content: ActivityContent(state: state, staleDate: next.when),
                                  pushType: nil)
    }

    static func makeState(_ x: ScheduleItem, _ when: Date) -> NextUpAttributes.ContentState {
        let timeLabel: String
        if x.kind == .timetable {
            timeLabel = x.time + " – " + (x.end % 1440 == 0 && x.end > 0 ? "24:00" : Day.clock(x.end))
        } else {
            timeLabel = x.time
        }
        return NextUpAttributes.ContentState(
            itemID: x.id,
            title: x.title,
            place: x.place,
            kindLabel: x.kind == .timetable ? "시간표" : "약속",
            timeLabel: timeLabel,
            colorHex: Palette.hex[min(max(x.color, 0), Palette.hex.count - 1)],
            from: Date(),
            start: when)
    }
}
