import SwiftUI

enum EditorSheet: Identifiable {
    case schedule(ScheduleItem, isNew: Bool)
    case todo(TodoItem, isNew: Bool)

    var id: String {
        switch self {
        case .schedule(let x, _): return "s-" + x.id
        case .todo(let t, _): return "t-" + t.id
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    /// 본문은 즉시 바뀌고, 탭바의 선택 표시만 부드럽게 움직인다
    @State private var tab: Tab = .home
    @State private var barTab: Tab = .home
    @State private var sheet: EditorSheet?
    /// 잠금화면 카드의 '못 했어'로 열린 연장 화면
    @State private var extend: ExtendRequest?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home: HomeView(sheet: $sheet)
                case .timetable: TimetableView(sheet: $sheet)
                case .calendar: CalendarScreen(sheet: $sheet)
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selected: barTab) { t in
                tab = t
                withAnimation(.easeOut(duration: 0.15)) { barTab = t }
            }
        }
        .tint(Theme.accent)
        .sheet(item: $sheet) { s in
            switch s {
            case .schedule(let item, let isNew):
                ScheduleEditor(item: item, isNew: isNew)
                    .environmentObject(store)
            case .todo(let todo, let isNew):
                TodoEditor(todo: todo, isNew: isNew)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $extend) { r in
            ExtendSheet(request: r).environmentObject(store)
        }
        .onOpenURL { url in
            if let r = ExtendRequest(url: url) { extend = r }
        }
        .preferredColorScheme(store.settings.theme.scheme)
        .task {
            _ = await NotificationScheduler.shared.requestAuthorization()
            store.reschedule()
            await CyberCampus.syncIfNeeded(store: store, minInterval: 60)
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            if phase == .active { LiveActivityManager.tickIfNeeded(store: store) }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active {
                store.reschedule()
                Task { await CyberCampus.syncIfNeeded(store: store) }
            }
            if newPhase == .background { CyberCampus.scheduleBackground() }
        }
        .alert("저장 오류", isPresented: Binding(get: { store.lastError != nil },
                                              set: { if !$0 { store.lastError = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
