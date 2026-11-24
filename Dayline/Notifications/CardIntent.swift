import ActivityKit
import AppIntents
import Foundation

/// 단축어용: 앱을 열지 않고 잠금화면 '다음 일정' 카드를 띄운다.
/// LiveActivityIntent라서 iOS가 백그라운드에서도 카드를 새로 시작하게 해준다.
/// 자동화로 자주 돌리니 결과 창은 띄우지 않고 조용히 끝낸다.
struct ShowNextCardIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "다음 일정 카드 띄우기"
    static var description = IntentDescription("3시간 안에 시작하는 다음 일정을 잠금화면과 다이내믹 아일랜드 카드로 띄워요. 앱은 열리지 않고, 결과 창도 뜨지 않아요.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = Store.shared
        await CyberCampus.syncIfNeeded(store: store)
        if store.settings.liveActivity, LiveActivityManager.isAvailable {
            await LiveActivityManager.refreshNow(store: store)
        }
        return .result()
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
