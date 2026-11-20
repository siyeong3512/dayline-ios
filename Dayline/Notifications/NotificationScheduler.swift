import Foundation
import Intents
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
            content.title = Nag.title(settings: settings, item: p.item)
            content.body = Nag.body(settings: settings, item: p.item, minutesBefore: p.minutesBefore)
            content.threadIdentifier = Nag.sender(settings: settings).map { "sender-" + $0 } ?? p.item.id
            content.sound = .default
            let chat = Self.usesChatStyle(settings)
            if !chat, let photo = Self.avatarAttachment(settings: settings) { content.attachments = [photo] }
            if settings.voiceEnabled {
                let text = Nag.spoken(settings: settings, item: p.item, minutesBefore: p.minutesBefore)
                if let name = await voice.soundFile(text: text, voiceID: settings.voiceID) {
                    usedSounds.insert(name)
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
                }
                // 목소리 파일을 만드는 동안 일정이 또 바뀌었으면 이번 작업은 버린다
                guard gen == generation else { return }
            }
            let final: UNNotificationContent = chat ? Self.chatContent(content, settings: settings) : content
            requests.append(UNNotificationRequest(identifier: p.id, content: final, trigger: p.trigger))
        }

        guard gen == generation else { return }
        center.removeAllPendingNotificationRequests()
        for r in requests { try? await center.add(r) }
        voice.cleanup(keeping: usedSounds)
    }

    /// 나만의 말투 + 프로필 사진이 있으면 알림 오른쪽에 사진을 붙인다.
    /// iOS가 첨부 파일을 옮겨 가므로 알림마다 복사본을 만든다.
    static func avatarAttachment(settings: AppSettings) -> UNNotificationAttachment? {
        guard settings.effectiveTone == .custom else { return nil }
        let fm = FileManager.default
        let source = Store.avatarURL
        guard fm.fileExists(atPath: source.path) else { return nil }
        let copy = fm.temporaryDirectory.appendingPathComponent("avatar-\(UUID().uuidString).jpg")
        do {
            try fm.copyItem(at: source, to: copy)
            return try UNNotificationAttachment(identifier: "avatar", url: copy, options: nil)
        } catch {
            try? fm.removeItem(at: copy)
            return nil
        }
    }

    /// 5초 뒤 테스트 알림
    func sendTest(settings: AppSettings) async {
        let sample = ScheduleItem(id: "test", kind: .event, title: "자료구조", place: "K501",
                                  time: Day.clock(Day.minutesOfDay(Date()) + 30), reminders: [30])
        let content = UNMutableNotificationContent()
        content.title = Nag.title(settings: settings, item: sample)
        content.body = Nag.body(settings: settings, item: sample, minutesBefore: 30)
        content.sound = .default
        let chat = Self.usesChatStyle(settings)
        if !chat, let photo = Self.avatarAttachment(settings: settings) { content.attachments = [photo] }
        if settings.voiceEnabled,
           let name = await voice.soundFile(text: Nag.spoken(settings: settings, item: sample, minutesBefore: 30),
                                            voiceID: settings.voiceID) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        }
        let final: UNNotificationContent = chat ? Self.chatContent(content, settings: settings) : content
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "dayline-test-\(UUID().uuidString)",
                                                    content: final, trigger: trigger))
    }

    // MARK: 카톡처럼 (커뮤니케이션 알림, 실험)

    static func usesChatStyle(_ settings: AppSettings) -> Bool {
        settings.chatStyle && Nag.sender(settings: settings) != nil
    }

    /// 알림을 '보낸 사람이 있는 메시지'로 바꾼다. 앱 아이콘 자리에 보낸 사람 사진이 뜨고,
    /// 구석에 작게 Dayline 아이콘이 붙는다. 권한(서명)이 없으면 원래 알림 + 오른쪽 사진으로 돌아간다.
    static func chatContent(_ content: UNMutableNotificationContent, settings: AppSettings) -> UNNotificationContent {
        guard let sender = Nag.sender(settings: settings) else { return content }
        var image: INImage?
        if let data = try? Data(contentsOf: Store.avatarURL) { image = INImage(imageData: data) }
        let person = INPerson(personHandle: INPersonHandle(value: "dayline-sender", type: .unknown),
                              nameComponents: nil,
                              displayName: sender,
                              image: image,
                              contactIdentifier: nil,
                              customIdentifier: "dayline-sender")
        let intent = INSendMessageIntent(recipients: nil,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: content.body,
                                         speakableGroupName: nil,
                                         conversationIdentifier: "dayline-" + sender,
                                         serviceName: nil,
                                         sender: person,
                                         attachments: nil)
        if let image { intent.setImage(image, forParameterNamed: \.sender) }
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        if let updated = try? content.updating(from: intent) { return updated }
        // 권한이 없어서 실패: 오른쪽 사진 방식으로
        if let photo = avatarAttachment(settings: settings) { content.attachments = [photo] }
        return content
    }
}
