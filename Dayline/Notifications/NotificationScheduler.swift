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

    static func plans(items: [ScheduleItem], now: Date = Date(), limit: Int = 60) -> [Plan] {
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
        return Array(out.sorted { $0.next < $1.next }.prefix(max(limit, 0)))
    }

    // MARK: 할 일 체크 알림

    struct TodoPlan {
        let id: String
        let key: String
        let fire: Date
        let period: String
        let titles: [String]
    }

    /// 앞으로 7일 동안 매일 정한 시각에, 아직 안 끝낸 할 일이 있으면 알린다.
    /// Daily는 매일, Weekly는 일요일(또는 마감 요일), Monthly는 말일(또는 마감일)에 포함.
    /// 체크할 때마다 다시 계산하므로 다 끝낸 날의 알림은 사라진다.
    static func todoPlans(todos: [TodoItem], settings: AppSettings, now: Date = Date()) -> [TodoPlan] {
        guard settings.todoCheck else { return [] }
        let active = todos.filter { !$0.archived }
        guard !active.isEmpty else { return [] }
        let today = Day.cal.startOfDay(for: now)
        var out: [TodoPlan] = []
        for d in 0..<7 {
            let day = Day.add(today, d)
            let key = Day.key(day)
            guard let fire = Day.cal.date(byAdding: .minute, value: settings.todoCheckMinutes, to: day), fire > now else { continue }
            let isSunday = Day.weekday(day) == 0
            let isMonthEnd = Day.cal.component(.month, from: Day.add(day, 1)) != Day.cal.component(.month, from: day)
            let left = active.filter { t in
                guard !t.isDone(on: key) else { return false }
                switch t.cadence {
                case .daily: return true
                case .weekly: return isSunday || t.dueKey(on: key) == key
                case .monthly: return isMonthEnd || t.dueKey(on: key) == key
                }
            }
            guard !left.isEmpty else { continue }
            let period = left.contains { $0.cadence == .monthly } ? "이번 달"
                : left.contains { $0.cadence == .weekly } ? "이번 주" : "오늘"
            let titles = left.sorted { $0.cadence.order < $1.cadence.order }.map(\.title)
            out.append(TodoPlan(id: "todo|\(key)", key: key, fire: fire, period: period, titles: titles))
        }
        return out
    }

    static func todoBody(_ p: TodoPlan, settings: AppSettings) -> String {
        let line = Nag.todoLine(settings: settings, period: p.period, count: p.titles.count, seed: p.key)
        let shown = p.titles.prefix(3).joined(separator: " · ")
        let more = p.titles.count > 3 ? " 외 \(p.titles.count - 3)개" : ""
        return line + "\n" + shown + more
    }

    // MARK: 예약

    func reschedule(items: [ScheduleItem], todos: [TodoItem], settings: AppSettings) async {
        generation += 1
        let gen = generation
        let todoList = Self.todoPlans(todos: todos, settings: settings)
        let budget = Self.limit - todoList.count - 1
        let list = Self.plans(items: items, limit: budget)
        var requests: [UNNotificationRequest] = []
        var usedSounds = Set<String>()

        for p in list {
            let thread = Nag.sender(settings: settings).map { "sender-" + $0 } ?? p.item.id
            let spoken = Nag.spoken(settings: settings, item: p.item, minutesBefore: p.minutesBefore)
            let body = Nag.body(settings: settings, item: p.item, minutesBefore: p.minutesBefore)
            // 말투에 줄바꿈이 있으면 톡처럼 2초 간격으로 여러 번 나눠 보낸다 (정보 줄은 마지막 조각에)
            var parts = body.components(separatedBy: "\n")
            let info = parts.count > 1 ? parts.removeLast() : nil
            let chunks = settings.effectiveTone == .plain ? [body] : Nag.pieces(parts.joined(separator: "\n"))
            guard requests.count + chunks.count <= budget else { break }
            for (k, chunk) in chunks.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = Nag.title(settings: settings, item: p.item)
                if k == chunks.count - 1, let info, settings.effectiveTone != .plain {
                    content.body = chunk + "\n" + info
                } else {
                    content.body = chunk
                }
                // 같은 묶음이면 잠금화면에서 한 장으로 접혀 보여서, 나눠 보낸 조각은 묶음을 따로 준다
                content.threadIdentifier = k == 0 ? thread : thread + "|\(k)"
                guard let decorated = await decorate(content, spoken: spoken, settings: settings, gen: gen, used: &usedSounds) else { return }
                var final = decorated
                if k > 0, let m = decorated.mutableCopy() as? UNMutableNotificationContent {
                    // 뒤 조각은 목소리 대신 짧은 기본음 (목소리를 켰으면 조용히)
                    m.sound = settings.voiceEnabled ? nil : .default
                    final = m
                }
                requests.append(UNNotificationRequest(identifier: k == 0 ? p.id : p.id + "|\(k)", content: final,
                                                      trigger: Self.shifted(p.trigger, seconds: k * 2)))
            }
        }

        for p in todoList {
            let content = UNMutableNotificationContent()
            content.title = Nag.sender(settings: settings) ?? "할 일 체크"
            content.body = Self.todoBody(p, settings: settings)
            content.threadIdentifier = "todo-check"
            let spoken = Nag.speakable(Nag.todoLine(settings: settings, period: p.period, count: p.titles.count, seed: p.key))
            guard let final = await decorate(content, spoken: spoken, settings: settings, gen: gen, used: &usedSounds) else { return }
            let comps = Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
            requests.append(UNNotificationRequest(identifier: p.id, content: final,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        // '못 했어'로 연장한 마감이 끝날 때 한 번 더 알림
        if let e = settings.extended, e.until > Date(), let item = items.first(where: { $0.id == e.itemID }) {
            let content = UNMutableNotificationContent()
            content.title = Nag.sender(settings: settings) ?? item.title
            content.body = "연장한 시간 끝! \(item.title) 잘 마무리했어?"
            content.threadIdentifier = "extend"
            content.sound = .default
            let comps = Day.cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: e.until)
            requests.append(UNNotificationRequest(identifier: "extend-" + e.itemID, content: content,
                                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        guard gen == generation else { return }
        center.removeAllPendingNotificationRequests()
        for r in requests { try? await center.add(r) }
        voice.cleanup(keeping: usedSounds)
    }

    /// 같은 시각 + n초 (나눠 보내는 뒷 조각용)
    static func shifted(_ t: UNCalendarNotificationTrigger, seconds: Int) -> UNCalendarNotificationTrigger {
        guard seconds > 0 else { return t }
        var c = t.dateComponents
        c.second = (c.second ?? 0) + seconds
        return UNCalendarNotificationTrigger(dateMatching: c, repeats: t.repeats)
    }

    /// 소리(목소리)·사진·카톡식 처리를 붙인다. 그 사이 일정이 또 바뀌었으면 nil
    private func decorate(_ content: UNMutableNotificationContent, spoken: String, settings: AppSettings,
                          gen: Int, used: inout Set<String>) async -> UNNotificationContent? {
        content.sound = .default
        let chat = Self.usesChatStyle(settings)
        if !chat, let photo = Self.avatarAttachment(settings: settings) { content.attachments = [photo] }
        if settings.voiceEnabled {
            if let name = await voice.soundFile(text: spoken, voiceID: settings.voiceID) {
                used.insert(name)
                content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
            }
            guard gen == generation else { return nil }
        }
        return chat ? Self.chatContent(content, settings: settings) : content
    }

    /// 보낸 사람 사진이 있으면 알림 오른쪽에 붙인다.
    /// iOS가 첨부 파일을 옮겨 가므로 알림마다 복사본을 만든다.
    static func avatarAttachment(settings: AppSettings) -> UNNotificationAttachment? {
        let fm = FileManager.default
        guard let source = Store.activeAvatarURL(settings) else { return nil }
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
        var parts = content.body.components(separatedBy: "\n")
        let info = parts.count > 1 ? parts.removeLast() : nil
        let chunks = settings.effectiveTone == .plain ? [content.body] : Nag.pieces(parts.joined(separator: "\n"))
        for (k, chunk) in chunks.enumerated() {
            guard let c = content.mutableCopy() as? UNMutableNotificationContent else { continue }
            if k == chunks.count - 1, let info, settings.effectiveTone != .plain {
                c.body = chunk + "\n" + info
            } else {
                c.body = chunk
            }
            if k > 0 { c.sound = settings.voiceEnabled ? nil : .default }
            if k > 0 { c.threadIdentifier = content.threadIdentifier + "|\(k)" }
            if k > 0, !chat, let photo = Self.avatarAttachment(settings: settings) { c.attachments = [photo] }
            let final: UNNotificationContent = chat ? Self.chatContent(c, settings: settings) : c
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(5 + k * 2), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "dayline-test-\(UUID().uuidString)",
                                                        content: final, trigger: trigger))
        }
    }

    // MARK: 카톡처럼 (커뮤니케이션 알림, 실험)

    static func usesChatStyle(_ settings: AppSettings) -> Bool {
        chatSupported && settings.chatStyle && Nag.sender(settings: settings) != nil
    }

    /// 설치할 때 받은 서명(프로비저닝 프로필)에 커뮤니케이션 알림 권한이 실제로 들어 있는지.
    /// 무료 계정 + SideStore는 이 권한을 빼고 서명해서, 없으면 iOS가 왼쪽 사진을 그리지 않는다.
    static let chatSupported: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return false }
        return data.range(of: Data("com.apple.developer.usernotifications.communication".utf8)) != nil
    }()

    /// 알림을 '보낸 사람이 있는 메시지'로 바꾼다. 앱 아이콘 자리에 보낸 사람 사진이 뜨고,
    /// 구석에 작게 Dayline 아이콘이 붙는다. 권한(서명)이 없으면 원래 알림 + 오른쪽 사진으로 돌아간다.
    static func chatContent(_ content: UNMutableNotificationContent, settings: AppSettings) -> UNNotificationContent {
        guard let sender = Nag.sender(settings: settings) else { return content }
        var image: INImage?
        if let url = Store.activeAvatarURL(settings), let data = try? Data(contentsOf: url) { image = INImage(imageData: data) }
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
