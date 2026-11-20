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
    case plain, gentle, friend, strict
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plain: return "담백하게"
        case .gentle: return "순한 응원"
        case .friend: return "친구처럼"
        case .strict: return "빡센 잔소리"
        }
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

struct AppSettings: Codable, Equatable {
    var tone: NagTone = .friend
    var voiceEnabled = false
    var voiceID: String?
    var theme: ThemeMode = .system

    init() {}

    enum CodingKeys: String, CodingKey { case tone, voiceEnabled, voiceID, theme }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tone = (try? c.decode(NagTone.self, forKey: .tone)) ?? .friend
        voiceEnabled = (try? c.decode(Bool.self, forKey: .voiceEnabled)) ?? false
        voiceID = try? c.decode(String.self, forKey: .voiceID)
        theme = (try? c.decode(ThemeMode.self, forKey: .theme)) ?? .system
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
