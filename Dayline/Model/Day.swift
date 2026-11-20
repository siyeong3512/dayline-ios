import Foundation

/// 날짜는 웹앱과 같은 "yyyy-MM-dd" 문자열 키로 다룬다. 요일은 0=일 … 6=토.
enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ko_KR")
        c.timeZone = .current
        return c
    }()

    static let names = ["일", "월", "화", "수", "목", "금", "토"]
    /// 월요일부터 시작하는 요일 순서
    static let mondayFirst = [1, 2, 3, 4, 5, 6, 0]

    static var today: String { key(Date()) }

    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func date(_ key: String) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else {
            return cal.startOfDay(for: Date())
        }
        return d
    }

    static func isValidKey(_ key: String) -> Bool {
        key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func isValidTime(_ s: String) -> Bool {
        s.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }

    static func add(_ d: Date, _ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func weekday(_ d: Date) -> Int { cal.component(.weekday, from: d) - 1 }
    static func weekday(_ key: String) -> Int { weekday(date(key)) }

    static func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }

    static func clock(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }

    /// 해당 날짜 키 + "HH:mm" 시각
    static func at(_ key: String, _ hhmm: String) -> Date {
        cal.date(byAdding: .minute, value: minutes(hhmm), to: date(key)) ?? date(key)
    }

    static func minutesOfDay(_ d: Date) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func time(fromMinutes m: Int) -> Date {
        cal.date(byAdding: .minute, value: ((m % 1440) + 1440) % 1440, to: cal.startOfDay(for: Date())) ?? Date()
    }

    static func weekStart(_ d: Date) -> Date {
        add(cal.startOfDay(for: d), -((weekday(d) + 6) % 7))
    }

    static func week(_ key: String) -> [Date] {
        let s = weekStart(date(key))
        return (0..<7).map { add(s, $0) }
    }

    static func firstOfMonth(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
    }

    static func monthCells(_ key: String) -> [Date] {
        let first = firstOfMonth(date(key))
        let offset = (weekday(first) + 6) % 7
        let length = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let total = Int((Double(offset + length) / 7).rounded(.up)) * 7
        return (0..<total).map { add(first, $0 - offset) }
    }

    static func sameMonth(_ a: Date, _ b: Date) -> Bool {
        cal.component(.month, from: a) == cal.component(.month, from: b)
            && cal.component(.year, from: a) == cal.component(.year, from: b)
    }

    static func format(_ d: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    static func nowMillis() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }
}
