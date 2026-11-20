import Foundation
import UserNotifications

/// 알림은 서버 없이 아이폰이 직접 예약한다(로컬 알림).
/// iOS는 앱당 대기 중인 알림을 64개까지만 두므로, 가장 가까운 60개를 예약하고 앱을 열 때마다 다시 채운다.
/// 시간표는 매주 반복 알림 하나로 처리해서 몇 주가 지나도 계속 울린다.
actor NotificationScheduler {
    static let shared = NotificationScheduler()
    static let limit = 60

    private let center = UNUserNotificationCenter.current()
    private let voice = VoiceMaker()
    private var generation = 0

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }

    struct Plan {
        let id: String
        let item: ScheduleItem
        let minutesBefore: Int
        let next: Date
        let trigger: UNCalendarNotificationTrigger
    }

    static func plans(items: [ScheduleItem], now: Date = Date()) -> [Plan] {
        let cal = Day.cal
        let todayKey = Day.key(now)
        var out: [Plan] = []

        func oneShot(_ id: String, _ item: ScheduleItem, _ n: Int, _ fire: Date) {
            guard fire > now else { return }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            out.append(Plan(id: id, item: item, minutesBefore: n, next: fire,
                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        for item in items {
            for n in item.reminders {
                switch item.kind {
                case .event:
                    let fire = Day.at(item.date, item.time).addingTimeInterval(TimeInterval(-n * 60))
                    oneShot("e|\(item.id)|\(n)", item, n, fire)

                case .timetable:
                    for wd in item.weekdays {
                        if item.date <= todayKey {
                            // 한 주(10080분) 안에서 알림 시각을 계산: 9시 수업의 '하루 전'은 전날 9시
                            let m = (((wd * 1440 + item.start - n) % 10080) + 10080) % 10080
                            var comps = DateComponents()
                            comps.weekday = m / 1440 + 1
                            comps.hour = (m % 1440) / 60
                            comps.minute = m % 60
                            guard let next = cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) else { continue }
                            out.append(Plan(id: "t|\(item.id)|\(wd)|\(n)", item: item, minutesBefore: n, next: next,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
                        } else {
                            // 반복 시작일이 미래면 첫 2주만 한 번씩 예약(시작일이 지나 앱을 열면 반복 알림으로 바뀜)
                            var d = Day.date(item.date)
                            while Day.weekday(d) != wd { d = Day.add(d, 1) }
                            for k in 0..<2 {
                                let key = Day.key(Day.add(d, 7 * k))
                                let fire = Day.at(key, item.time).addingTimeInterval(TimeInterval(-n * 60))
                                oneShot("t1|\(item.id)|\(wd)|\(n)|\(k)", item, n, fire)
                            }
                        }
                    }
                }
            }
        }
        return Array(out.sorted { $0.next < $1.next }.prefix(limit))
    }

    func reschedule(items: [ScheduleItem], settings: AppSettings) async {
        generation += 1
        let gen = generation
        let list = Self.plans(items: items)
        var requests: [UNNotificationRequest] = []
        var usedSounds = Set<String>()

        for p in list {
            let content = UNMutableNotificationContent()
            content.title = p.item.title
            content.body = Nag.body(tone: settings.tone, item: p.item, minutesBefore: p.minutesBefore)
            content.threadIdentifier = p.item.id
            content.sound = .default
            if settings.voiceEnabled {
                let text = Nag.spoken(tone: settings.tone, item: p.item, minutesBefore: p.minutesBefore)
                if let name = await voice.soundFile(text: text, voiceID: settings.voiceID) {
                    usedSounds.insert(name)
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
                }
                // 목소리 파일을 만드는 동안 일정이 또 바뀌었으면 이번 작업은 버린다
                guard gen == generation else { return }
            }
            requests.append(UNNotificationRequest(identifier: p.id, content: content, trigger: p.trigger))
        }

        guard gen == generation else { return }
        center.removeAllPendingNotificationRequests()
        for r in requests { try? await center.add(r) }
        voice.cleanup(keeping: usedSounds)
    }

    /// 5초 뒤 테스트 알림
    func sendTest(settings: AppSettings) async {
        let sample = ScheduleItem(id: "test", kind: .event, title: "자료구조", place: "K501",
                                  time: Day.clock(Day.minutesOfDay(Date()) + 30), reminders: [30])
        let content = UNMutableNotificationContent()
        content.title = sample.title
        content.body = Nag.body(tone: settings.tone, item: sample, minutesBefore: 30)
        content.sound = .default
        if settings.voiceEnabled,
           let name = await voice.soundFile(text: Nag.spoken(tone: settings.tone, item: sample, minutesBefore: 30),
                                            voiceID: settings.voiceID) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "dayline-test-\(UUID().uuidString)",
                                                    content: content, trigger: trigger))
    }
}
