import AVFoundation
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ExportFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("dayline-backup.json")
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var auth: UNAuthorizationStatus = .notDetermined
    @State private var pending = 0
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var importing = false
    @State private var notice: String?
    @State private var speaker = AVSpeechSynthesizer()

    private let sample = ScheduleItem(id: "sample", kind: .timetable, title: "자료구조", place: "K501",
                                      time: "14:00", weekdays: [1], reminders: [30])

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                toneSection
                voiceSection
                Section("화면") {
                    Picker("테마", selection: $store.settings.theme) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                }
                dataSection
                sideStoreSection
            }
            .navigationTitle("설정")
            .contentMargins(.bottom, 90, for: .scrollContent)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
                importFile(result)
            }
            .alert("Dayline", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
            .task { await refresh() }
            .onChange(of: phase) { _, p in if p == .active { Task { await refresh() } } }
        }
    }

    private func refresh() async {
        auth = await NotificationScheduler.shared.status()
        pending = await NotificationScheduler.shared.pendingCount()
        voices = VoiceMaker.voices()
    }

    // MARK: 알림

    private var notificationSection: some View {
        Section {
            LabeledContent("상태", value: authLabel)
            LabeledContent("예약된 알림", value: "\(pending)개")
            if auth == .notDetermined {
                Button("알림 허용하기") {
                    Task {
                        _ = await NotificationScheduler.shared.requestAuthorization()
                        store.reschedule()
                        await refresh()
                    }
                }
            } else if auth == .denied {
                Button("설정 앱에서 알림 켜기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button("5초 뒤 테스트 알림") {
                Task {
                    await NotificationScheduler.shared.sendTest(settings: store.settings)
                    notice = "5초 뒤에 알림이 와요. 앱을 닫거나 화면을 꺼서 확인해 보세요."
                }
            }
        } header: {
            Text("알림")
        } footer: {
            Text("알림은 아이폰이 직접 예약해서 보내요. 서버·인터넷이 필요 없고 ‘from 데이라인’ 표시도 없어요. 한 번에 최대 \(NotificationScheduler.limit)개까지 예약되고, 앱을 열 때마다 다시 채워요.")
        }
    }

    private var authLabel: String {
        switch auth {
        case .authorized: return "허용됨"
        case .provisional, .ephemeral: return "임시 허용"
        case .denied: return "꺼짐"
        case .notDetermined: return "아직 묻지 않음"
        @unknown default: return "알 수 없음"
        }
    }

    // MARK: 잔소리

    private var toneSection: some View {
        Section {
            Picker("말투", selection: $store.settings.tone) {
                ForEach(NagTone.allCases) { Text($0.label).tag($0) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("미리보기 · 자료구조 30분 전").font(.caption).foregroundStyle(.secondary)
                Text(Nag.body(tone: store.settings.tone, item: sample, minutesBefore: 30))
                    .font(.subheadline)
            }
            .padding(.vertical, 2)
        } header: {
            Text("잔소리")
        }
    }

    // MARK: 목소리

    private var voiceSection: some View {
        Section {
            Toggle("목소리로 알림", isOn: $store.settings.voiceEnabled)
            if store.settings.voiceEnabled {
                Picker("목소리", selection: $store.settings.voiceID) {
                    Text("기본 한국어").tag(String?.none)
                    ForEach(voices, id: \.identifier) { v in
                        Text(voiceName(v)).tag(Optional(v.identifier))
                    }
                }
                Button("미리 듣기") {
                    speaker.stopSpeaking(at: .immediate)
                    let u = AVSpeechUtterance(string: Nag.spoken(tone: store.settings.tone, item: sample, minutesBefore: 30))
                    u.voice = VoiceMaker.voice(for: store.settings.voiceID)
                    speaker.speak(u)
                }
                Button("개인 음성 사용 허용") {
                    AVSpeechSynthesizer.requestPersonalVoiceAuthorization { _ in
                        DispatchQueue.main.async { voices = VoiceMaker.voices() }
                    }
                }
            }
        } header: {
            Text("목소리 알림")
        } footer: {
            Text("잔소리를 음성 파일로 만들어 알림음으로 재생해요. 무음 모드·집중 모드에서는 소리가 안 날 수 있어요. 더 자연스러운 목소리는 설정 > 손쉬운 사용 > 읽기 및 말하기 > 음성에서 ‘향상된’ 한국어 음성을 내려받으면 여기에 나타나요. 개인 음성은 내 아이폰에서 내 목소리로 만든 음성이에요.")
        }
    }

    private func voiceName(_ v: AVSpeechSynthesisVoice) -> String {
        if v.voiceTraits.contains(.isPersonalVoice) { return v.name + " (개인 음성)" }
        switch v.quality {
        case .premium: return v.name + " (프리미엄)"
        case .enhanced: return v.name + " (향상됨)"
        default: return v.name
        }
    }

    // MARK: 데이터

    private var dataSection: some View {
        Section {
            Button {
                importing = true
            } label: {
                Label("웹앱 기록 가져오기 (JSON)", systemImage: "square.and.arrow.down")
            }
            ShareLink(item: ExportFile(data: store.exportData()),
                      preview: SharePreview("Dayline 백업", image: Image(systemName: "doc.text"))) {
                Label("전체 내보내기", systemImage: "square.and.arrow.up")
            }
            NavigationLink {
                BackupListView()
            } label: {
                Label("자동 백업에서 복구", systemImage: "clock.arrow.circlepath")
            }
        } header: {
            Text("데이터")
        } footer: {
            Text("시간표 \(store.timetable.count)개 · 약속 \(store.items.count - store.timetable.count)개 · 할 일 \(store.todos.filter { !$0.archived }.count)개. 기록은 아이폰 안에 저장되고, 바뀔 때마다 자동 백업(최대 30개)을 남겨요. 앱을 삭제하면 같이 지워지니 가끔 내보내기 해두세요.")
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            notice = "파일을 열지 못했어요: \(e.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let r = try store.importData(data)
                notice = "일정·시간표 \(r.items)개, 할 일 \(r.todos)개를 가져왔어요. 가져오기 전 상태도 자동 백업해뒀어요."
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    // MARK: SideStore

    private var sideStoreSection: some View {
        Section {
            LabeledContent("버전", value: appVersion)
        } header: {
            Text("앱 정보")
        } footer: {
            Text("SideStore로 설치한 앱은 서명이 7일마다 만료돼요. 단축어 자동화로 매일 갱신하도록 설정해 두면 신경 쓸 필요 없어요. 갱신·업데이트 방법은 저장소 README에 있어요.")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct BackupListView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var target: Store.Backup?
    @State private var list: [Store.Backup] = []

    var body: some View {
        List {
            if list.isEmpty {
                Text("아직 자동 백업이 없어요. 기록을 바꾸면 30분에 한 번씩 남겨요.").foregroundStyle(.secondary)
            }
            ForEach(list) { b in
                Button {
                    target = b
                } label: {
                    LabeledContent(Day.format(b.date, "yMMMdEEEjm"), value: "복구")
                }
            }
        }
        .navigationTitle("자동 백업")
        .contentMargins(.bottom, 90, for: .scrollContent)
        .onAppear { list = store.backups() }
        .confirmationDialog("이 시점으로 되돌릴까요?", isPresented: Binding(get: { target != nil },
                                                                 set: { if !$0 { target = nil } }),
                            titleVisibility: .visible) {
            Button("되돌리기", role: .destructive) {
                if let b = target {
                    try? store.restore(b)
                    list = store.backups()
                    dismiss()
                }
            }
        } message: {
            Text("지금 상태도 먼저 백업해두기 때문에 다시 돌아올 수 있어요.")
        }
    }
}
