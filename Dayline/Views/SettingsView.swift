import AVFoundation
import CoreTransferable
import PhotosUI
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

    /// 할 일 체크 시각 (설정은 분 단위로 저장)
    private var todoTime: Binding<Date> {
        Binding(get: { Day.time(fromMinutes: store.settings.todoCheckMinutes) },
                set: { store.settings.todoCheckMinutes = Day.minutesOfDay($0) })
    }

    /// 기본 말투 고르기: "b:friend"(기본 제공) 또는 "c:<보관함 id>"
    private var toneChoice: Binding<String> {
        Binding(get: {
            let s = store.settings
            return s.tone == .custom ? "c:" + (s.customToneID ?? "") : "b:" + s.tone.rawValue
        }, set: { v in
            var s = store.settings
            if v.hasPrefix("c:") {
                s.tone = .custom
                s.customToneID = String(v.dropFirst(2))
            } else {
                s.tone = NagTone(rawValue: String(v.dropFirst(2))) ?? .friend
            }
            store.settings = s
        })
    }

    private let sample = ScheduleItem(id: "sample", kind: .timetable, title: "자료구조", place: "K501",
                                      time: "14:00", weekdays: [1], reminders: [30])

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                todoCheckSection
                liveActivitySection
                CyberCampusSection()
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
            .alert("핑", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
            .task { await refresh() }
            .onChange(of: phase) { _, p in if p == .active { Task { await refresh() } } }
        }
    }

    // MARK: 할 일 체크

    private var todoCheckSection: some View {
        Section {
            Toggle("할 일 체크 알림", isOn: $store.settings.todoCheck)
            if store.settings.todoCheck {
                DatePicker("알림 시각", selection: todoTime, displayedComponents: .hourAndMinute)
                VStack(alignment: .leading, spacing: 4) {
                    Text("미리보기").font(.caption).foregroundStyle(.secondary)
                    Text(Nag.todoLine(settings: store.settings, period: "오늘", count: 2, seed: "preview"))
                        .font(.subheadline)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("할 일 체크")
        } footer: {
            Text("이 시각에 아직 안 끝낸 할 일이 있으면 알려줘요. Daily는 매일, Weekly는 일요일(또는 마감 요일), Monthly는 말일(또는 마감일)에 함께 챙겨요. 다 체크한 날은 알림이 오지 않아요.")
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

    // MARK: 라이브 액티비티

    private var liveActivitySection: some View {
        Section {
            Toggle("다음 일정 카드", isOn: $store.settings.liveActivity)
            if store.settings.liveActivity {
                Button("다음 일정으로 지금 띄워보기") {
                    if !LiveActivityManager.isAvailable {
                        notice = "아이폰 설정 > 핑 > 실시간 현황(라이브 액티비티)이 꺼져 있어요. 켠 뒤 다시 눌러주세요."
                    } else if store.upNext() == nil {
                        notice = "다가오는 일정이 없어요. 시간표나 약속을 먼저 추가해 주세요."
                    } else {
                        LiveActivityManager.rerollLine()
                        LiveActivityManager.refresh(store: store, force: true)
                        notice = "잠금화면과 다이내믹 아일랜드를 확인해 보세요. 안 보이면 SideStore 설치 때 확장 처리 방식을 바꿔야 할 수 있어요."
                    }
                }
            }
        } header: {
            Text("잠금화면 · 다이내믹 아일랜드")
        } footer: {
            Text("다음 일정이 3시간 안이면 앱을 열 때 잠금화면과 다이내믹 아일랜드에 카운트다운 카드가 떠요. iOS 제한 때문에 앱을 연 뒤에만 새로 시작되고, 최대 8시간까지 유지돼요.")
        }
    }

    // MARK: 잔소리

    private var toneSection: some View {
        Section {
            Picker("기본 말투", selection: toneChoice) {
                ForEach([NagTone.plain, .gentle, .friend, .strict]) { t in
                    Text(t.label).tag("b:" + t.rawValue)
                }
                ForEach(store.settings.toneLibrary) { t in
                    Text(t.name).tag("c:" + t.id)
                }
            }
            if let p = store.settings.activePerson, p.tone != nil {
                Text("지금은 \(p.name)의 말투(\(PersonToneView.label(p, settings: store.settings)))로 보내요. 보낸 사람 > 수정 > 말투에서 바꿔요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("미리보기").font(.caption).foregroundStyle(.secondary)
                ForEach([1440, 30, 10], id: \.self) { n in
                    Text("· \(ReminderOption.label(n)): " + Nag.line(settings: store.settings, item: sample, minutesBefore: n))
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 2)

            NavigationLink {
                PeopleView()
            } label: {
                HStack(spacing: 12) {
                    AvatarView(personID: store.settings.activePerson?.id, version: store.avatarVersion, size: 36)
                    Text("보낸 사람")
                    Spacer()
                    Text(store.settings.activePerson?.name ?? "없음").foregroundStyle(.secondary)
                }
            }

            let personID = store.settings.activePerson?.id
            let hasPhoto = Store.activeAvatarURL(store.settings) != nil
            let chat = NotificationScheduler.usesChatStyle(store.settings)
            NotificationPreview(title: Nag.title(settings: store.settings, item: sample),
                                message: Nag.body(settings: store.settings, item: sample, minutesBefore: 30),
                                showsPhoto: hasPhoto && !chat,
                                personID: personID,
                                version: store.avatarVersion,
                                chatStyle: chat)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))

            if store.settings.activePerson != nil {
                Toggle(isOn: $store.settings.chatStyle) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("카톡처럼 왼쪽에 사진 (실험)")
                        Text(NotificationScheduler.chatSupported
                             ? "앱 아이콘 자리에 프로필 사진이 떠요."
                             : "지금 서명(무료 계정)에는 이 권한이 없어서 사진은 오른쪽에 붙어요. 유료 개발자 계정으로 설치하면 켜져요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(!NotificationScheduler.chatSupported)
            }

            NavigationLink {
                ToneLibraryView()
            } label: {
                LabeledContent {
                    Text("\(store.settings.toneLibrary.count)개")
                } label: {
                    Label("말투 보관함", systemImage: "text.bubble")
                }
            }
        } header: {
            Text("잔소리")
        } footer: {
            Text("기본 말투는 보낸 사람이 없거나, 그 사람에게 말투를 따로 정하지 않았을 때 써요. 보낸 사람마다 말투를 따로 정하려면 보낸 사람 > 수정 > 말투로 가요. 보낸 사람의 이름이 알림 제목이 되고 사진은 알림 오른쪽과 잠금화면 카드에 붙어요. 나만의 말투는 말투 보관함에 파일(dayline-tone)을 여러 개 넣어두고 골라 써요. 문장에 을/를, 이/가, (으)로, (이)처럼 쓰면 일정 이름의 받침에 맞게 골라줘요. 문장과 사진은 이 아이폰 안에만 저장돼요.")
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
                    let u = AVSpeechUtterance(string: Nag.spoken(settings: store.settings, item: sample, minutesBefore: 30))
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
                      preview: SharePreview("핑 백업", image: Image(systemName: "doc.text"))) {
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
                if let tone = CustomTone.decodeFile(data) {
                    let added = store.addTone(tone)
                    notice = "‘\(added.name)’ 말투를 보관함에 넣었어요 (문장 \(added.count)개). 기본 말투나 보낸 사람 > 말투에서 골라 쓰세요."
                    return
                }
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
