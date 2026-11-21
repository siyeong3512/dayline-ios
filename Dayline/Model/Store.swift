import Foundation
import SwiftUI

/// 모든 기록은 아이폰 안(Application Support/Dayline)에 JSON으로 저장한다.
/// 저장할 때마다 이전 파일을 Backups 폴더에 남긴다(30분에 1개, 최대 30개).
final class Store: ObservableObject {
    /// 앱·백그라운드 작업·단축어가 같은 저장소를 쓰도록 하나만 만든다
    static let shared = Store()

    @Published private(set) var items: [ScheduleItem] = []
    @Published private(set) var todos: [TodoItem] = []
    @Published var settings = AppSettings() {
        didSet {
            guard !isLoading, settings != oldValue else { return }
            save()
            reschedule()
        }
    }
    @Published var lastError: String?

    private var isLoading = false
    private let dir: URL
    private var fileURL: URL { dir.appendingPathComponent("dayline.json") }
    var backupDir: URL { dir.appendingPathComponent("Backups", isDirectory: true) }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Dayline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Backups", isDirectory: true),
                                                 withIntermediateDirectories: true)
        load()
        afterLoad()
    }

    // MARK: 저장

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(DaylineData.self, from: data)
            items = decoded.items
            todos = decoded.todos
            if let s = decoded.settings { settings = s }
        } catch {
            let name = "corrupt-\(Int(Date().timeIntervalSince1970)).json"
            try? FileManager.default.copyItem(at: fileURL, to: backupDir.appendingPathComponent(name))
            lastError = "저장 파일을 읽지 못했어요. 설정 > 자동 백업에서 복구할 수 있어요."
        }
    }

    /// 앱 시작 때 한 번: 예전 데이터 옮기기
    private func afterLoad() {
        migrateLegacySender()
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = DaylineData(items: items, todos: todos, settings: settings)
        do {
            let data = try Self.encoder.encode(snapshot)
            if FileManager.default.fileExists(atPath: fileURL.path) { backup(force: false) }
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            lastError = "저장하지 못했어요: \(error.localizedDescription)"
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: 자동 백업

    struct Backup: Identifiable, Hashable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    func backups() -> [Backup] {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url -> Backup? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("backup-"), let ts = Double(name.dropFirst("backup-".count)) else { return nil }
            return Backup(url: url, date: Date(timeIntervalSince1970: ts))
        }
        .sorted { $0.date > $1.date }
    }

    private func backup(force: Bool) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let existing = backups()
        if !force, let latest = existing.first, Date().timeIntervalSince(latest.date) < 1800 { return }
        let url = backupDir.appendingPathComponent("backup-\(Int(Date().timeIntervalSince1970)).json")
        try? fm.removeItem(at: url)
        try? fm.copyItem(at: fileURL, to: url)
        for old in backups().dropFirst(30) { try? fm.removeItem(at: old.url) }
    }

    func restore(_ b: Backup) throws {
        let data = try Data(contentsOf: b.url)
        let decoded = try JSONDecoder().decode(DaylineData.self, from: data)
        backup(force: true)
        items = decoded.items
        todos = decoded.todos
        commit()
    }

    // MARK: 가져오기·내보내기

    enum ImportError: LocalizedError {
        case empty
        var errorDescription: String? { "앱 기록을 찾지 못했어요. 내보내기 한 JSON 파일인지 확인해 주세요." }
    }

    /// 웹앱 내보내기 파일 또는 이 앱의 백업 파일을 합친다. 같은 id는 가져온 쪽이 이긴다(할 일은 최신 수정본).
    @discardableResult
    func importData(_ data: Data) throws -> (items: Int, todos: Int) {
        let decoder = JSONDecoder()
        var incoming = (try? decoder.decode(DaylineData.self, from: data)) ?? DaylineData(items: [], todos: [])
        if incoming.items.isEmpty && incoming.todos.isEmpty {
            if let arr = try? decoder.decode([Lossy<ScheduleItem>].self, from: data) {
                incoming.items = arr.compactMap(\.value)
            }
            if incoming.items.isEmpty, let arr = try? decoder.decode([Lossy<TodoItem>].self, from: data) {
                incoming.todos = arr.compactMap(\.value)
            }
        }
        guard !(incoming.items.isEmpty && incoming.todos.isEmpty) else { throw ImportError.empty }

        backup(force: true)
        var itemMap: [String: ScheduleItem] = [:]
        for x in items { itemMap[x.id] = x }
        for x in incoming.items { itemMap[x.id] = x }
        var todoMap: [String: TodoItem] = [:]
        for t in todos { todoMap[t.id] = t }
        for t in incoming.todos where (todoMap[t.id]?.updatedAt ?? -1) <= t.updatedAt { todoMap[t.id] = t }

        items = Self.uniqueOrder(items.map(\.id) + incoming.items.map(\.id)).compactMap { itemMap[$0] }
        todos = Self.uniqueOrder(todos.map(\.id) + incoming.todos.map(\.id)).compactMap { todoMap[$0] }
        commit()
        return (incoming.items.count, incoming.todos.count)
    }

    private static func uniqueOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    func exportData() -> Data {
        (try? Self.encoder.encode(DaylineData(items: items, todos: todos, settings: settings))) ?? Data()
    }

    // MARK: 시간표·약속

    func upsert(_ item: ScheduleItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        commit()
    }

    func delete(_ item: ScheduleItem) {
        if item.id.hasPrefix(CyberCampus.idPrefix) { CyberCampus.ignored.insert(item.id) }
        items.removeAll { $0.id == item.id }
        commit()
    }

    func events(on key: String, kind: ItemKind = .event) -> [ScheduleItem] {
        items.filter { $0.kind == kind && $0.occurs(on: key) }.sorted { $0.time < $1.time }
    }

    var timetable: [ScheduleItem] { items.filter { $0.kind == .timetable } }

    func nextOccurrence(_ x: ScheduleItem, after now: Date) -> Date? {
        if x.kind == .event {
            let when = Day.at(x.date, x.time)
            return when >= now ? when : nil
        }
        let todayKey = Day.key(now)
        let base = todayKey > x.date ? Day.date(todayKey) : Day.date(x.date)
        for i in 0..<8 {
            let key = Day.key(Day.add(base, i))
            let when = Day.at(key, x.time)
            if x.occurs(on: key) && when >= now { return when }
        }
        return nil
    }

    func upNext(now: Date = Date()) -> (item: ScheduleItem, when: Date)? {
        var best: (item: ScheduleItem, when: Date)?
        for x in items {
            guard let when = nextOccurrence(x, after: now) else { continue }
            if best == nil || when < best!.when { best = (item: x, when: when) }
        }
        return best
    }

    // MARK: 할 일

    func activeTodos(filter: Cadence?, on key: String) -> [TodoItem] {
        todos.filter { !$0.archived && (filter == nil || $0.cadence == filter) }
            .sorted { a, b in
                let ad = a.isDone(on: key), bd = b.isDone(on: key)
                if ad != bd { return !ad }
                if a.cadence.order != b.cadence.order { return a.cadence.order < b.cadence.order }
                let au = a.dueKey(on: key) ?? "9999", bu = b.dueKey(on: key) ?? "9999"
                if au != bu { return au < bu }
                if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
                return a.id < b.id
            }
    }

    func upsertTodo(_ t: TodoItem) {
        var t = t
        let previous = todos.first { $0.id == t.id }?.updatedAt ?? 0
        t.updatedAt = max(Day.nowMillis(), previous + 1)
        if let i = todos.firstIndex(where: { $0.id == t.id }) { todos[i] = t } else { todos.append(t) }
        commit() // 할 일 체크 알림도 다시 계산
    }

    func archiveTodo(_ t: TodoItem) {
        var t = t
        t.archived = true
        upsertTodo(t)
    }

    func toggle(_ t: TodoItem, on key: String) {
        guard let i = todos.firstIndex(where: { $0.id == t.id }) else { return }
        var x = todos[i]
        let p = x.period(on: key)
        if x.completed[p] != nil { x.completed.removeValue(forKey: p) } else { x.completed[p] = Day.nowMillis() }
        x.updatedAt = max(Day.nowMillis(), x.updatedAt + 1)
        todos[i] = x
        commit() // 다 끝낸 날은 체크 알림이 빠지도록
    }

    // MARK: 보낸 사람 (이름 + 프로필 사진, 기기 안에만 저장)

    private static var baseDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayline", isDirectory: true)
    }

    /// 예전 버전의 사진 하나짜리 위치
    private static var legacyAvatarURL: URL { baseDir.appendingPathComponent("avatar.jpg") }

    static func avatarURL(for id: String) -> URL {
        baseDir.appendingPathComponent("avatars", isDirectory: true).appendingPathComponent("\(id).jpg")
    }

    /// 지금 쓰는 사람의 사진 (없으면 nil)
    static func activeAvatarURL(_ settings: AppSettings) -> URL? {
        guard let id = settings.activePerson?.id else { return nil }
        let url = avatarURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @Published private(set) var avatarVersion = 0

    func hasAvatar(_ id: String) -> Bool { FileManager.default.fileExists(atPath: Self.avatarURL(for: id).path) }

    func setAvatar(_ data: Data?, for id: String) {
        let url = Self.avatarURL(for: id)
        if let data {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            } catch {
                lastError = "사진을 저장하지 못했어요: \(error.localizedDescription)"
                return
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        avatarVersion += 1
        reschedule()
    }

    /// 사람 추가·수정. 이름이 비면 저장하지 않는다
    func upsertPerson(_ p: Person, makeActive: Bool) {
        var s = settings
        if let i = s.people.firstIndex(where: { $0.id == p.id }) { s.people[i] = p } else { s.people.append(p) }
        if makeActive { s.activePersonID = p.id }
        settings = s
    }

    func deletePerson(_ p: Person) {
        var s = settings
        s.people.removeAll { $0.id == p.id }
        if s.activePersonID == p.id { s.activePersonID = nil }
        try? FileManager.default.removeItem(at: Self.avatarURL(for: p.id))
        avatarVersion += 1
        settings = s
    }

    func setActivePerson(_ id: String?) {
        var s = settings
        s.activePersonID = id
        settings = s
    }

    /// 예전 버전(말투 파일의 sender + 사진 하나)을 '보낸 사람' 목록으로 옮긴다
    private func migrateLegacySender() {
        guard settings.people.isEmpty else { return }
        let fm = FileManager.default
        let hasLegacyPhoto = fm.fileExists(atPath: Self.legacyAvatarURL.path)
        let legacyName = settings.toneLibrary.first(where: { $0.sender != nil })?.sender
        guard hasLegacyPhoto || legacyName != nil else { return }
        let person = Person(name: legacyName ?? "보낸 사람")
        if hasLegacyPhoto {
            let target = Self.avatarURL(for: person.id)
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: Self.legacyAvatarURL, to: target)
        }
        var s = settings
        s.people = [person]
        s.activePersonID = person.id
        for i in s.toneLibrary.indices { s.toneLibrary[i].sender = nil }
        settings = s
    }

    // MARK: 말투 보관함

    /// 보관함에 넣는다. 같은 이름이 있으면 새 문장으로 바꾼다(쓰던 곳은 그대로)
    @discardableResult
    func addTone(_ tone: CustomTone) -> CustomTone {
        var t = tone
        t.sender = nil
        var s = settings
        if let i = s.toneLibrary.firstIndex(where: { $0.name == t.name }) {
            t.id = s.toneLibrary[i].id
            s.toneLibrary[i] = t
        } else {
            s.toneLibrary.append(t)
        }
        settings = s
        return t
    }

    func renameTone(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = settings.toneLibrary.firstIndex(where: { $0.id == id }) else { return }
        settings.toneLibrary[i].name = name
    }

    /// 지우면 이 말투를 쓰던 곳은 기본값으로 돌아간다
    func deleteTone(_ id: String) {
        var s = settings
        s.toneLibrary.removeAll { $0.id == id }
        if s.customToneID == id {
            s.customToneID = nil
            if s.tone == .custom { s.tone = .friend }
        }
        for i in s.people.indices where s.people[i].customToneID == id {
            s.people[i].customToneID = nil
            if s.people[i].tone == .custom { s.people[i].tone = nil }
        }
        settings = s
    }

    /// 이 말투를 쓰는 곳 ("기본", 사람 이름)
    func toneUsers(_ id: String) -> [String] {
        var out: [String] = []
        if settings.tone == .custom && settings.customToneID == id { out.append("기본") }
        out += settings.people.filter { $0.tone == .custom && $0.customToneID == id }.map(\.name)
        return out
    }

    // MARK: 알림

    private func commit() {
        save()
        reschedule()
    }

    // MARK: 사이버캠퍼스

    /// 가져온 과제·시험을 약속으로 넣는다. 이미 있으면 시각·제목만 고치고(알림·색은 그대로),
    /// 목록에서 사라진(제출한) 앞으로의 항목은 지운다. 반영한 개수를 돌려준다.
    @discardableResult
    func applyCyber(_ entries: [CyberCampus.Entry]) -> Int {
        let ignored = CyberCampus.ignored
        let now = Date()
        var changed = false
        var keep = Set<String>()
        for e in entries {
            let id = CyberCampus.idPrefix + e.seq
            keep.insert(id)
            guard !ignored.contains(id), e.due > now else { continue }
            let course = CyberCampus.shortCourse(e.course)
            let title = (course.isEmpty ? "" : course + " ") + e.name
            let date = Day.key(e.due)
            let time = Day.clock(Day.minutesOfDay(e.due))
            if let i = items.firstIndex(where: { $0.id == id }) {
                var x = items[i]
                if x.title != title || x.date != date || x.time != time {
                    x.title = title; x.date = date; x.time = time
                    items[i] = x
                    changed = true
                }
            } else {
                let color = Int(Nag.stableHash(e.course) % UInt64(Palette.colors.count))
                items.append(ScheduleItem(id: id, kind: .event, title: title, place: "",
                                          date: date, time: time, duration: 60,
                                          color: color, reminders: [1440, 180, 60]))
                changed = true
            }
        }
        let before = items.count
        items.removeAll { x in
            x.id.hasPrefix(CyberCampus.idPrefix) && !keep.contains(x.id) && Day.at(x.date, x.time) > now
        }
        if items.count != before { changed = true }
        if changed { commit() }
        return entries.filter { $0.due > now }.count
    }

    // MARK: 마무리 체크

    /// '못 했어' → n분 연장. 연장한 시각에 카드와 알림으로 다시 묻는다.
    func extend(itemID: String, start: Date, minutes: Int) {
        ResultLog.clearDone(itemID: itemID, around: start)
        ResultLog.record(ResultLog.key(itemID, start), done: false)
        settings.extended = Extension(itemID: itemID, until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// '오늘은 그만할래'
    func giveUp(itemID: String, start: Date) {
        ResultLog.clearDone(itemID: itemID, around: start)
        ResultLog.record(ResultLog.key(itemID, start), done: false)
        if settings.extended?.itemID == itemID { settings.extended = nil } else { reschedule() }
    }

    /// 오늘 이 일정을 '했어'로 마무리했는지
    func finished(_ item: ScheduleItem, on key: String) -> Bool {
        // 연장 중이면 아직 안 끝난 것
        if let e = settings.extended, e.itemID == item.id, e.until > Date() { return false }
        let prefix = item.id + "|"
        let dayStart = Day.date(key), dayEnd = Day.add(dayStart, 1)
        return ResultLog.all().contains { k, done in
            guard done, k.hasPrefix(prefix), let t = Double(k.dropFirst(prefix.count)) else { return false }
            let d = Date(timeIntervalSince1970: t)
            return d >= dayStart && d < dayEnd
        }
    }

    func reschedule() {
        let snapshotItems = items
        let snapshotTodos = todos
        let snapshotSettings = settings
        Task {
            await NotificationScheduler.shared.reschedule(items: snapshotItems, todos: snapshotTodos, settings: snapshotSettings)
        }
        LiveActivityManager.refresh(store: self)
    }
}
