import SwiftUI

// MARK: - 색상·알림 옵션

enum Palette {
    static let hex = ["6c8ee8", "a079cc", "dc9a51", "58a8a0", "cd7d98", "d46565",
                      "79a84c", "d3ac35", "4eafd0", "645ac4", "ad7955", "788594"]
    static let names = ["파랑", "보라", "주황", "청록", "분홍", "빨강",
                        "초록", "노랑", "하늘", "남보라", "갈색", "회색"]
    static let colors: [Color] = hex.map { Color(hex: $0) }

    static func color(_ i: Int) -> Color { colors[min(max(i, 0), colors.count - 1)] }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}

enum ReminderOption {
    static let all = [10, 30, 60, 120, 180, 1440]

    static func label(_ n: Int) -> String {
        n == 1440 ? "하루 전" : n >= 60 ? "\(n / 60)시간 전" : "\(n)분 전"
    }

    /// "30분", "1시간", "하루"
    static func amount(_ n: Int) -> String {
        n == 1440 ? "하루" : n >= 60 ? "\(n / 60)시간" : "\(n)분"
    }
}

// MARK: - 시간표·약속

enum ItemKind: String, Codable { case timetable, event }

struct ScheduleItem: Identifiable, Codable, Hashable {
    var id: String
    var kind: ItemKind
    var title: String
    var place: String
    /// 약속: 날짜 / 시간표: 반복 시작일
    var date: String
    /// "HH:mm"
    var time: String
    /// 분 단위. 약속은 표시용으로만 씀
    var duration: Int
    /// 시간표 반복 요일(0=일)
    var weekdays: [Int]
    var color: Int
    var reminders: [Int]

    init(id: String = UUID().uuidString, kind: ItemKind, title: String = "", place: String = "",
         date: String = Day.today, time: String = "09:00", duration: Int = 60,
         weekdays: [Int] = [], color: Int = 0, reminders: [Int] = [30]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.place = place
        self.date = date
        self.time = time
        self.duration = duration
        self.weekdays = weekdays
        self.color = color
        self.reminders = reminders
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, place, date, time, duration, weekdays, color, reminders
    }

    /// 웹앱 JSON(필드 누락·옛 형식 포함)도 읽을 수 있게 관대하게 디코딩
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = (try? c.decode(ItemKind.self, forKey: .kind)) ?? .timetable
        title = try c.decode(String.self, forKey: .title)
        place = (try? c.decode(String.self, forKey: .place)) ?? ""
        let d = try c.decode(String.self, forKey: .date)
        let t = try c.decode(String.self, forKey: .time)
        guard Day.isValidKey(d), Day.isValidTime(t) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "날짜·시간 형식 오류")
        }
        date = d
        time = t
        let rawDuration = (try? c.decode(Double.self, forKey: .duration)) ?? 60
        duration = min(max(Int(rawDuration), 1), 2880)
        let rawColor = (try? c.decode(Int.self, forKey: .color)) ?? 0
        color = min(max(rawColor, 0), Palette.colors.count - 1)
        let rawReminders = (try? c.decode([Int].self, forKey: .reminders)) ?? []
        reminders = Array(Set(rawReminders.filter { ReminderOption.all.contains($0) })).sorted()
        let rawWeekdays = (try? c.decode([Int].self, forKey: .weekdays)) ?? []
        if kind == .timetable {
            let valid = Array(Set(rawWeekdays.filter { (0...6).contains($0) })).sorted()
            weekdays = valid.isEmpty ? [Day.weekday(d)] : valid
        } else {
            weekdays = []
        }
    }

    var start: Int { Day.minutes(time) }
    var end: Int { start + duration }

    func occurs(on key: String) -> Bool {
        switch kind {
        case .event: return date == key
        case .timetable: return key >= date && weekdays.contains(Day.weekday(key))
        }
    }

    var detailLine: String {
        var s = time
        if kind == .timetable {
            s += " – " + (end >= 1440 && end % 1440 == 0 ? "24:00" : Day.clock(end))
            if end > 1440 { s += " (다음 날)" }
        }
        if !place.isEmpty { s += " · " + place }
        return s
    }
}

// MARK: - 할 일

enum Cadence: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
    var korean: String {
        switch self {
        case .daily: return "매일"
        case .weekly: return "매주"
        case .monthly: return "매월"
        }
    }
    var order: Int {
        switch self {
        case .daily: return 0
        case .weekly: return 1
        case .monthly: return 2
        }
    }
    var help: String {
        switch self {
        case .daily: return "매일 새 체크리스트가 시작돼요. 기준일 이후에는 매일 오늘이 마감일이에요."
        case .weekly: return "매주 월요일에 새로 시작해요. 기준일의 요일이 매주 마감 요일이 돼요."
        case .monthly: return "매월 1일에 새로 시작해요. 기준일의 날짜가 매월 마감일이 돼요. 없는 날짜는 말일로 맞춰요."
        }
    }
    var tint: Color {
        switch self {
        case .daily: return Palette.color(0)
        case .weekly: return Palette.color(3)
        case .monthly: return Palette.color(2)
        }
    }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var cadence: Cadence
    /// 마감 기준일 "yyyy-MM-dd" (없으면 nil)
    var due: String?
    /// 주기 키("d:2026-11-20", "w:2026-11-16", "m:2026-11") → 완료 시각(ms)
    var completed: [String: Double]
    var archived: Bool
    var updatedAt: Double

    init(id: String = UUID().uuidString, title: String = "", cadence: Cadence = .daily, due: String? = nil,
         completed: [String: Double] = [:], archived: Bool = false, updatedAt: Double = Day.nowMillis()) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.due = due
        self.completed = completed
        self.archived = archived
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case id, title, cadence, due, completed, archived, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        cadence = (try? c.decode(Cadence.self, forKey: .cadence)) ?? .daily
        let rawDue = (try? c.decode(String.self, forKey: .due)) ?? ""
        due = Day.isValidKey(rawDue) ? rawDue : nil
        completed = (try? c.decode([String: Double].self, forKey: .completed)) ?? [:]
        archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? Day.nowMillis()
    }

    func period(on key: String) -> String {
        switch cadence {
        case .daily: return "d:" + key
        case .weekly: return "w:" + Day.key(Day.weekStart(Day.date(key)))
        case .monthly: return "m:" + String(key.prefix(7))
        }
    }

    func isDone(on key: String) -> Bool { completed[period(on: key)] != nil }

    /// 이번 주기의 마감일 키
    func dueKey(on key: String) -> String? {
        guard let due else { return nil }
        let anchor = Day.date(due)
        let today = Day.date(key)
        let d: Date
        switch cadence {
        case .daily:
            d = today
        case .weekly:
            d = Day.add(Day.weekStart(today), (Day.weekday(anchor) + 6) % 7)
        case .monthly:
            let first = Day.firstOfMonth(today)
            let length = Day.cal.range(of: .day, in: .month, for: first)?.count ?? 28
            d = Day.add(first, min(Day.cal.component(.day, from: anchor), length) - 1)
        }
        let k = Day.key(d)
        return k < due ? due : k
    }
}

// MARK: - 설정

enum NagTone: String, Codable, CaseIterable, Identifiable {
    case plain, gentle, friend, strict, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plain: return "담백하게"
        case .gentle: return "순한 응원"
        case .friend: return "친구처럼"
        case .strict: return "빡센 잔소리"
        case .custom: return "나만의 말투"
        }
    }
}

/// 사용자가 파일로 가져오는 말투. 앱 안(설정 파일)에만 저장되고 코드·저장소에는 들어가지 않는다.
/// 문장 안의 {title} {left} {place} {time}은 일정 정보로 바뀐다.
struct CustomTone: Codable, Hashable, Identifiable {
    /// 보관함 안에서 구분하는 값 (파일에는 없어도 됨)
    var id: String = UUID().uuidString
    var name: String
    /// 알림 제목에 보낸 사람처럼 표시할 이름(없으면 일정 이름이 제목)
    var sender: String?
    /// 2시간 이상 전
    var early: [String]
    /// 30분~1시간 전
    var soon: [String]
    /// 10분 전
    var urgent: [String]
    /// 할 일 체크 알림 ({period} {count} 사용)
    var todo: [String]
    /// 잠금화면 카드 전용 문장 (없으면 알림 문장을 쓴다)
    var cardEarly: [String] = []
    var cardSoon: [String] = []
    var cardUrgent: [String] = []

    enum CodingKeys: String, CodingKey { case id, name, sender, early, soon, urgent, todo, cardEarly, cardSoon, cardUrgent }

    init(name: String, sender: String? = nil, early: [String], soon: [String], urgent: [String], todo: [String] = []) {
        self.name = name
        self.sender = sender
        self.early = early
        self.soon = soon
        self.urgent = urgent
        self.todo = todo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "나만의 말투"
        let rawSender = ((try? c.decode(String.self, forKey: .sender)) ?? "").trimmingCharacters(in: .whitespaces)
        sender = rawSender.isEmpty ? nil : rawSender
        early = ((try? c.decode([String].self, forKey: .early)) ?? []).filter { !$0.isEmpty }
        soon = ((try? c.decode([String].self, forKey: .soon)) ?? []).filter { !$0.isEmpty }
        urgent = ((try? c.decode([String].self, forKey: .urgent)) ?? []).filter { !$0.isEmpty }
        todo = ((try? c.decode([String].self, forKey: .todo)) ?? []).filter { !$0.isEmpty }
        cardEarly = ((try? c.decode([String].self, forKey: .cardEarly)) ?? []).filter { !$0.isEmpty }
        cardSoon = ((try? c.decode([String].self, forKey: .cardSoon)) ?? []).filter { !$0.isEmpty }
        cardUrgent = ((try? c.decode([String].self, forKey: .cardUrgent)) ?? []).filter { !$0.isEmpty }
    }

    var isUsable: Bool { !(early.isEmpty && soon.isEmpty && urgent.isEmpty) }
    var count: Int { early.count + soon.count + urgent.count + todo.count + cardEarly.count + cardSoon.count + cardUrgent.count }

    /// 카드 전용 문장 (단계가 비면 다른 단계로 채운다, 전부 없으면 빈 배열)
    func cardPool(stage: Int) -> [String] {
        let order: [[String]]
        switch stage {
        case 0: order = [cardEarly, cardSoon, cardUrgent]
        case 1: order = [cardSoon, cardEarly, cardUrgent]
        default: order = [cardUrgent, cardSoon, cardEarly]
        }
        return order.first { !$0.isEmpty } ?? []
    }

    /// 비어 있는 단계는 다른 단계 문장으로 채운다
    func pool(stage: Int) -> [String] {
        let order: [[String]]
        switch stage {
        case 0: order = [early, soon, urgent]
        case 1: order = [soon, early, urgent]
        default: order = [urgent, soon, early]
        }
        return order.first { !$0.isEmpty } ?? []
    }

    /// {"format": "dayline-tone", ...} 파일인지 확인하고 읽는다
    static func decodeFile(_ data: Data) -> CustomTone? {
        struct Header: Decodable { let format: String? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == "dayline-tone",
              let tone = try? JSONDecoder().decode(CustomTone.self, from: data),
              tone.isUsable else { return nil }
        return tone
    }
}

enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "아이폰 설정 따라가기"
        case .light: return "밝게"
        case .dark: return "어둡게"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 알림을 보내는 사람(이름 + 프로필 사진). 사진은 Application Support/Dayline/avatars/<id>.jpg
/// tone이 nil이면 설정 > 잔소리의 기본 말투를 따라간다. customTone은 이 사람 전용 말투 파일.
struct Person: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var tone: NagTone?
    /// tone이 .custom일 때 쓰는 보관함 말투 id
    var customToneID: String?
    /// 옛 버전에서 사람마다 넣던 말투 (보관함으로 옮긴 뒤 비움)
    var customTone: CustomTone?
    /// 잠금화면 카드·다이내믹 아일랜드 색 (PersonColor.hex 중 하나, nil이면 기본 라벤더)
    var colorHex: String?
}

/// 보낸 사람 색: 빨강부터 분홍까지 모든 계열, 톤은 라벤더와 비슷하게(밝고 살짝 부드러운 정도)
enum PersonColor {
    static let all: [(hex: String, name: String)] = [
        ("E05A5A", "레드"), ("E8775A", "코랄"), ("EB8F45", "오렌지"), ("E5A93A", "앰버"),
        ("D9BB3A", "옐로"), ("A8C24A", "라임"), ("6CBF5A", "그린"), ("3FB98A", "에메랄드"),
        ("3DB8A8", "민트"), ("3AAFC0", "틸"), ("4DA6E6", "스카이"), ("4F86E8", "블루"),
        ("5A6EE6", "코발트"), ("7B5CE6", "라벤더"), ("A05CE0", "퍼플"), ("E05FA8", "핑크")
    ]
    static let defaultHex = "7B5CE6"
}

/// '못 했어'로 연장한 마감
struct Extension: Codable, Equatable {
    var itemID: String
    var until: Date
}

struct AppSettings: Codable, Equatable {
    var tone: NagTone = .friend
    var voiceEnabled = false
    var voiceID: String?
    var theme: ThemeMode = .system
    var customTone: CustomTone?
    /// 실험: 카톡처럼 왼쪽에 보낸 사람 사진(커뮤니케이션 알림)
    var chatStyle = false
    /// 잠금화면·다이내믹 아일랜드 '다음 일정' 카드
    var liveActivity = true
    /// 보낸 사람 목록과 지금 쓰는 사람(nil이면 일정 이름이 알림 제목)
    var people: [Person] = []
    var activePersonID: String?
    /// 할 일 체크 알림
    var todoCheck = true
    /// 체크 시각(자정부터 분). 기본 밤 9시
    var todoCheckMinutes = 21 * 60
    /// 연장 중인 일정
    var extended: Extension?
    /// 가져온 말투들
    var toneLibrary: [CustomTone] = []
    /// 기본 말투가 .custom일 때 쓰는 보관함 말투 id
    var customToneID: String?

    init() {}

    enum CodingKeys: String, CodingKey {
        case tone, voiceEnabled, voiceID, theme, customTone, chatStyle, liveActivity
        case people, activePersonID, todoCheck, todoCheckMinutes, extended, toneLibrary, customToneID
    }

    var activePerson: Person? {
        guard let id = activePersonID else { return nil }
        return people.first { $0.id == id }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tone = (try? c.decode(NagTone.self, forKey: .tone)) ?? .friend
        voiceEnabled = (try? c.decode(Bool.self, forKey: .voiceEnabled)) ?? false
        voiceID = try? c.decode(String.self, forKey: .voiceID)
        theme = (try? c.decode(ThemeMode.self, forKey: .theme)) ?? .system
        customTone = try? c.decode(CustomTone.self, forKey: .customTone)
        chatStyle = (try? c.decode(Bool.self, forKey: .chatStyle)) ?? false
        liveActivity = (try? c.decode(Bool.self, forKey: .liveActivity)) ?? true
        people = (try? c.decode([Person].self, forKey: .people)) ?? []
        activePersonID = try? c.decode(String.self, forKey: .activePersonID)
        todoCheck = (try? c.decode(Bool.self, forKey: .todoCheck)) ?? true
        let rawMinutes = (try? c.decode(Int.self, forKey: .todoCheckMinutes)) ?? 21 * 60
        todoCheckMinutes = min(max(rawMinutes, 0), 1439)
        extended = try? c.decode(Extension.self, forKey: .extended)
        toneLibrary = (try? c.decode([CustomTone].self, forKey: .toneLibrary)) ?? []
        customToneID = try? c.decode(String.self, forKey: .customToneID)
        migrateToLibrary()
    }

    /// 지금 쓰는 말투: 고른 사람에게 따로 정한 말투가 있으면 그것, 없으면 기본 말투
    var currentTone: NagTone { activePerson?.tone ?? tone }
    /// 지금 쓰는 나만의 말투 파일
    var currentCustom: CustomTone? {
        if let p = activePerson, p.tone != nil { return libraryTone(p.customToneID) }
        return libraryTone(customToneID)
    }

    func libraryTone(_ id: String?) -> CustomTone? {
        guard let id else { return nil }
        return toneLibrary.first { $0.id == id }
    }

    /// 옛 버전의 말투 하나(기본·사람별)를 보관함으로 옮긴다
    private mutating func migrateToLibrary() {
        if let t = customTone {
            if !toneLibrary.contains(where: { $0.id == t.id }) { toneLibrary.append(t) }
            if customToneID == nil { customToneID = t.id }
            customTone = nil
        }
        for i in people.indices {
            guard let t = people[i].customTone else { continue }
            if let same = toneLibrary.first(where: { $0.name == t.name && $0.count == t.count }) {
                people[i].customToneID = same.id
            } else {
                toneLibrary.append(t)
                people[i].customToneID = t.id
            }
            people[i].customTone = nil
        }
    }

    /// 나만의 말투를 골랐는데 파일이 없으면 '친구처럼'으로
    var effectiveTone: NagTone {
        currentTone == .custom && !(currentCustom?.isUsable ?? false) ? .friend : currentTone
    }
}

// MARK: - 저장 파일 / 내보내기 형식

/// 배열 안에 깨진 항목이 있어도 나머지는 살린다
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct DaylineData: Codable {
    var format = "dayline-export"
    var version = 1
    var items: [ScheduleItem]
    var todos: [TodoItem]
    var settings: AppSettings?

    init(items: [ScheduleItem], todos: [TodoItem], settings: AppSettings? = nil) {
        self.items = items
        self.todos = todos
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case format, version, items, todos, settings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(String.self, forKey: .format)) ?? "dayline-export"
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        items = ((try? c.decode([Lossy<ScheduleItem>].self, forKey: .items)) ?? []).compactMap(\.value)
        todos = ((try? c.decode([Lossy<TodoItem>].self, forKey: .todos)) ?? []).compactMap(\.value)
        settings = try? c.decode(AppSettings.self, forKey: .settings)
    }
}
