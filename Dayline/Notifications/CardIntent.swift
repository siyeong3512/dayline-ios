import ActivityKit
import AppIntents
import Foundation

/// 단축어용: 앱을 열지 않고 잠금화면 '다음 일정' 카드를 띄운다.
/// LiveActivityIntent라서 iOS가 백그라운드에서도 카드를 새로 시작하게 해준다.
struct ShowNextCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "다음 일정 카드 띄우기"
    static var description = IntentDescription("3시간 안에 시작하는 다음 일정을 잠금화면과 다이내믹 아일랜드 카드로 띄워요. 앱은 열리지 않아요.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        await CyberCampus.syncIfNeeded(store: store)
        guard store.settings.liveActivity else {
            return .result(dialog: "핑 설정에서 '다음 일정 카드'가 꺼져 있어요.")
        }
        guard LiveActivityManager.isAvailable else {
            return .result(dialog: "아이폰 설정 > 핑에서 실시간 현황을 켜주세요.")
        }
        let next = await LiveActivityManager.refreshNow(store: store)
        guard let next, next.when.timeIntervalSinceNow <= LiveActivityManager.window else {
            return .result(dialog: "3시간 안에 다가오는 일정이 없어요.")
        }
        if Activity<NextUpAttributes>.activities.isEmpty {
            return .result(dialog: "카드를 띄우지 못했어요. 핑을 한 번 열어주세요.")
        }
        return .result(dialog: "\(next.item.title) 카드를 띄웠어요.")
    }
}

/// 단축어 앱에 바로 보이는 동작들
struct PingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowNextCardIntent(),
                    phrases: ["\(.applicationName) 카드 띄워줘", "\(.applicationName) 다음 일정 카드"],
                    shortTitle: "다음 일정 카드",
                    systemImageName: "rectangle.badge.checkmark")
        AppShortcut(intent: SyncCyberIntent(),
                    phrases: ["\(.applicationName) 과제 가져와", "\(.applicationName) 사이버캠퍼스 동기화"],
                    shortTitle: "사이버캠퍼스 과제",
                    systemImageName: "graduationcap")
    }
}
