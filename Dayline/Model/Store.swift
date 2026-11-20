import Foundation
import SwiftUI

/// 모든 기록은 아이폰 안(Application Support/Dayline)에 JSON으로 저장한다.
/// 저장할 때마다 이전 파일을 Backups 폴더에 남긴다(30분에 1개, 최대 30개).
final class Store: ObservableObject {
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
        var errorDescription: String? { "Dayline 기록을 찾지 못했어요. 내보내기 한 JSON 파일인지 확인해 주세요." }
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
        save()
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
        save()
    }

    // MARK: 프로필 사진 (나만의 말투의 보낸 사람 사진, 기기 안에만 저장)

    static var avatarURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayline", isDirectory: true)
            .appendingPathComponent("avatar.jpg")
    }

    @Published private(set) var avatarVersion = 0

    var hasAvatar: Bool { FileManager.default.fileExists(atPath: Self.avatarURL.path) }

    func setAvatar(_ data: Data?) {
        if let data {
            do { try data.write(to: Self.avatarURL, options: [.atomic]) } catch {
                lastError = "사진을 저장하지 못했어요: \(error.localizedDescription)"
                return
            }
        } else {
            try? FileManager.default.removeItem(at: Self.avatarURL)
        }
        avatarVersion += 1
        reschedule()
    }

    // MARK: 알림

    private func commit() {
        save()
        reschedule()
    }

    func reschedule() {
        let snapshotItems = items
        let snapshotSettings = settings
        Task { await NotificationScheduler.shared.reschedule(items: snapshotItems, settings: snapshotSettings) }
    }
}
