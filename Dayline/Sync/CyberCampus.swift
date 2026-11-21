import AppIntents
import BackgroundTasks
import Foundation
import Security
import UserNotifications

/// 서강대 사이버캠퍼스(cyber.sogang.ac.kr)의 '할 일' 목록에서 과제·퀴즈·시험 마감을 가져온다.
/// 학번·비밀번호는 아이폰 키체인에만 저장하고, 로그인이 풀리면 그 값으로 다시 로그인한다.
enum CyberCampus {
    static let base = URL(string: "https://cyber.sogang.ac.kr")!
    /// 가져올 종류 (목록의 [ ] 안 이름)
    static let kinds: Set<String> = ["과제", "팀과제", "퀴즈", "중간시험", "기말시험"]
    static let idPrefix = "cyber-"

    struct Entry: Equatable {
        let seq: String
        let kind: String
        let name: String
        let course: String
        let due: Date
    }

    enum SyncError: LocalizedError {
        case noAccount, loginFailed, network(String), unexpected
        var errorDescription: String? {
            switch self {
            case .noAccount: return "사이버캠퍼스 계정이 연결되지 않았어요."
            case .loginFailed: return "로그인에 실패했어요. 학번·비밀번호를 확인해 주세요."
            case .network(let m): return "사이버캠퍼스에 연결하지 못했어요: \(m)"
            case .unexpected: return "사이버캠퍼스 화면이 예상과 달라요. 앱 업데이트가 필요할 수 있어요."
            }
        }
    }

    // MARK: 상태 (UserDefaults)

    private static let d = UserDefaults.standard
    static var lastSync: Date? {
        get { d.object(forKey: "cyberLastSync") as? Date }
        set { d.set(newValue, forKey: "cyberLastSync") }
    }
    static var lastMessage: String? {
        get { d.string(forKey: "cyberLastMessage") }
        set { d.set(newValue, forKey: "cyberLastMessage") }
    }
    /// 사용자가 지운 항목은 다시 넣지 않는다
    static var ignored: Set<String> {
        get { Set(d.stringArray(forKey: "cyberIgnored") ?? []) }
        set { d.set(Array(newValue.suffix(500)), forKey: "cyberIgnored") }
    }
    private static var loginAlertDay: String? {
        get { d.string(forKey: "cyberLoginAlertDay") }
        set { d.set(newValue, forKey: "cyberLoginAlertDay") }
    }

    static var isConnected: Bool { Keychain.get("id") != nil && Keychain.get("pw") != nil }

    static func connect(id: String, password: String) {
        Keychain.set(id, for: "id")
        Keychain.set(password, for: "pw")
    }

    static func disconnect() {
        Keychain.delete("id")
        Keychain.delete("pw")
        lastSync = nil
        lastMessage = nil
        HTTPCookieStorage.shared.cookies(for: base)?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }

    // MARK: 동기화

    private static var running = false

    /// 너무 자주 하지 않도록: 마지막 동기화 후 minInterval이 지났을 때만
    @MainActor
    static func syncIfNeeded(store: Store, minInterval: TimeInterval = 15 * 60) async {
        guard isConnected else { return }
        if let last = lastSync, Date().timeIntervalSince(last) < minInterval { return }
        _ = try? await sync(store: store)
    }

    /// 가져와서 일정에 반영. 반영한 항목 수를 돌려준다.
    @MainActor
    @discardableResult
    static func sync(store: Store) async throws -> Int {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        do {
            let entries = try await fetchEntries()
            let n = store.applyCyber(entries)
            lastSync = Date()
            lastMessage = "과제·시험 \(n)개"
            return n
        } catch let e as SyncError {
            lastMessage = e.errorDescription
            if case .loginFailed = e { notifyLoginProblem() }
            throw e
        }
    }

    static func fetchEntries() async throws -> [Entry] {
        guard let id = Keychain.get("id"), let pw = Keychain.get("pw") else { throw SyncError.noAccount }
        var html = try await todoHTML()
        if loggedOut(html) {
            try await login(id: id, password: pw)
            html = try await todoHTML()
            if loggedOut(html) { throw SyncError.loginFailed }
        }
        guard html.contains("todo_wrap") || html.contains("no_data") || html.count < 4000 else { throw SyncError.unexpected }
        return parse(html)
    }

    private static func loggedOut(_ html: String) -> Bool {
        html.contains("접속이 종료") || html.contains("login_form.acl")
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    private static func post(_ path: String, _ fields: [(String, String)]) async throws -> String {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.setValue(base.absoluteString + "/ilos/main/main_form.acl", forHTTPHeaderField: "Referer")
        r.httpBody = fields.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&").data(using: .utf8)
        do {
            let (data, _) = try await session.data(for: r)
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
    }

    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func todoHTML() async throws -> String {
        try await post("ilos/mp/todo_list.acl", [("todoKjList", ""), ("chk_cate", "ALL"), ("encoding", "utf-8")])
    }

    /// 사이트의 로그인 폼과 같은 값을 보낸다 ('로그인 유지' 켬)
    private static func login(id: String, password: String) async throws {
        // 세션 쿠키를 먼저 받는다
        _ = try? await session.data(from: base.appendingPathComponent("ilos/main/member/login_form.acl"))
        let res = try await post("ilos/lo/login.acl", [
            ("returnURL", ""), ("challenge", ""), ("response", ""), ("auto_login", "Y"),
            ("usr_id", id), ("usr_pwd", password), ("encoding", "utf-8"),
        ])
        if res.localizedCaseInsensitiveContains("captcha") { throw SyncError.loginFailed }
    }

    // MARK: 파싱

    static func parse(_ html: String) -> [Entry] {
        var out: [Entry] = []
        var seen = Set<String>()
        let blocks = html.components(separatedBy: "<a class=\"todo_wrap").dropFirst()
        for raw in blocks {
            let block = raw.components(separatedBy: "</a>").first ?? raw
            guard let call = first(#"goLecture\('[^']*','([^']*)','([^']*)'\)"#, in: block),
                  let titleHTML = first(#"class="todo_title[^"]*">([\s\S]*?)</div>"#, in: block)?.first else { continue }
            let seq = call[1]
            let title = text(titleHTML)
            guard let kindRange = first(#"^\[([^\]]+)\]\s*(.*)$"#, in: title) else { continue }
            let kind = kindRange[0], name = kindRange[1]
            guard kinds.contains(kind) else { continue }
            let course = first(#"class="todo_subjt[^"]*">([\s\S]*?)</div>"#, in: block).map { text($0[0]) } ?? ""
            let dateText = firstGroups(#"<span class="todo_date">([\s\S]*?)</span>"#, in: block).last.map(text) ?? ""
            guard let due = parseDate(dateText) else { continue }
            let key = "\(kind)|\(name)|\(course)|\(Int(due.timeIntervalSince1970))"
            guard seen.insert(key).inserted else { continue } // 같은 과제가 두 번 올 때
            out.append(Entry(seq: seq, kind: kind, name: name, course: course, due: due))
        }
        return out
    }

    /// "11월 28일 (토) 오후 6:00" (기간이면 마지막 날짜)
    static func parseDate(_ s: String, now: Date = Date()) -> Date? {
        let ms = all(#"(\d{1,2})월\s*(\d{1,2})일[^0-9]*?(오전|오후)?\s*(\d{1,2}):(\d{2})"#, in: s, groups: 5)
        guard let m = ms.last, let mon = Int(m[0]), let day = Int(m[1]), var h = Int(m[3]), let mi = Int(m[4]) else { return nil }
        if m[2] == "오후" && h < 12 { h += 12 }
        if m[2] == "오전" && h == 12 { h = 0 }
        let cal = Day.cal
        let year = cal.component(.year, from: now)
        for y in [year, year + 1] {
            if let d = cal.date(from: DateComponents(year: y, month: mon, day: day, hour: h, minute: mi)),
               d > now.addingTimeInterval(-120 * 86400) { return d }
        }
        return nil
    }

    /// "운영체제(CSE4070-02)" → "운영체제"
    static func shortCourse(_ c: String) -> String {
        guard let i = c.lastIndex(of: "("), c.hasSuffix(")") else { return c }
        return String(c[..<i]).trimmingCharacters(in: .whitespaces)
    }

    private static func text(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func first(_ pattern: String, in s: String) -> [String]? {
        all(pattern, in: s, groups: nil).first
    }

    private static func all(_ pattern: String, in s: String, groups: Int?) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private static func firstGroups(_ pattern: String, in s: String) -> [String] {
        all(pattern, in: s, groups: nil).compactMap(\.first)
    }

    // MARK: 로그인 문제 알림 (하루 한 번)

    private static func notifyLoginProblem() {
        let today = Day.today
        guard loginAlertDay != today else { return }
        loginAlertDay = today
        let c = UNMutableNotificationContent()
        c.title = "사이버캠퍼스"
        c.body = "로그인이 안 돼서 과제를 못 가져왔어요. 핑 > 설정 > 사이버캠퍼스에서 다시 연결해 주세요."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cyber-login", content: c, trigger: nil))
    }
}

/// 사이버캠퍼스 학번·비밀번호 보관 (이 아이폰의 키체인)
enum Keychain {
    private static let service = "app.dayline.ios.cyber"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        // 잠금 해제 후 한 번이면 백그라운드 동기화에서도 읽을 수 있게
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

// MARK: - 백그라운드 · 단축어


extension CyberCampus {
    static let taskID = "app.dayline.ios.cyber"

    static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            scheduleBackground()
            Task { @MainActor in
                _ = try? await sync(store: Store.shared)
                task.setTaskCompleted(success: true)
            }
        }
    }

    /// 2시간쯤 뒤에 다시 가져오도록 iOS에 부탁한다 (정확한 시각은 iOS가 정함)
    static func scheduleBackground() {
        guard isConnected else { return }
        let r = BGAppRefreshTaskRequest(identifier: taskID)
        r.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }
}

/// 단축어 자동화용: "사이버캠퍼스 과제 가져오기"
struct SyncCyberIntent: AppIntent {
    static var title: LocalizedStringResource = "사이버캠퍼스 과제 가져오기"
    static var description = IntentDescription("서강대 사이버캠퍼스의 과제·퀴즈·시험 마감을 핑 일정으로 가져와요.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let n = try await CyberCampus.sync(store: Store.shared)
        return .result(dialog: "과제·시험 \(n)개를 확인했어요.")
    }
}
