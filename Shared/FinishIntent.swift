import ActivityKit
import AppIntents
import Foundation

/// 일정이 끝났는지(했어/못 했어) 기록. 키 = "일정id|시작시각(초)"
enum ResultLog {
    private static let defaultsKey = "finishResults"

    static func key(_ itemID: String, _ start: Date) -> String { "\(itemID)|\(Int(start.timeIntervalSince1970))" }

    static func all() -> [String: Bool] {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool]) ?? [:]
    }

    static func result(_ itemID: String, _ start: Date) -> Bool? { all()[key(itemID, start)] }

    static func record(_ key: String, done: Bool) {
        var d = all()
        d[key] = done
        // 오래된 기록은 정리 (최근 300개)
        if d.count > 300 {
            let old = d.keys.sorted { ($0.split(separator: "|").last.flatMap { Int($0) } ?? 0) < ($1.split(separator: "|").last.flatMap { Int($0) } ?? 0) }
            for k in old.prefix(d.count - 300) { d[k] = nil }
        }
        UserDefaults.standard.set(d, forKey: defaultsKey)
    }
}

/// 잠금화면 카드의 "했어" 버튼. 앱 프로세스에서 실행되고, 카드를 '잘했어' 상태로 바꾼 뒤 닫는다.
struct FinishIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "일정 마무리했어요"
    static var isDiscoverable = false

    @Parameter(title: "일정") var key: String

    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        ResultLog.record(key, done: true)
        for a in Activity<NextUpAttributes>.activities
        where ResultLog.key(a.content.state.itemID, a.content.state.start) == key {
            var s = a.content.state
            s.result = "done"
            await a.end(ActivityContent(state: s, staleDate: nil),
                        dismissalPolicy: .after(Date().addingTimeInterval(10 * 60)))
        }
        return .result()
    }
}
