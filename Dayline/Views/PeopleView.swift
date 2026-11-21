import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 설정 > 보낸 사람: 알림 제목에 쓸 이름과 프로필 사진을 여러 명 저장하고 골라 쓴다.
struct PeopleView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Person?
    @State private var isNew = false

    var body: some View {
        List {
            Section {
                Button {
                    store.setActivePerson(nil)
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "calendar", bg: Theme.pill, fg: Theme.faint, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("없음").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                            Text("알림 제목이 일정 이름으로 떠요").font(.system(size: 13)).foregroundStyle(Theme.faint)
                        }
                        Spacer()
                        if store.settings.activePersonID == nil {
                            Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(store.settings.people) { p in
                    HStack(spacing: 12) {
                        Button {
                            store.setActivePerson(p.id)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(personID: p.id, version: store.avatarVersion, size: 44)
                                    .overlay(Circle().strokeBorder(Color(hex: p.colorHex ?? PersonColor.defaultHex), lineWidth: 2.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                                    Text("말투: " + PersonToneView.label(p, settings: store.settings))
                                        .font(.system(size: 13)).foregroundStyle(Theme.faint)
                                }
                                Spacer()
                                if store.settings.activePersonID == p.id {
                                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("수정") {
                            isNew = false
                            editing = p
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.pillText)
                        .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("고른 사람의 이름이 알림 제목이 되고, 사진은 알림과 잠금화면 카드에 붙어요. 말투는 설정 > 잔소리에서 따로 골라요.")
            }

            Section {
                Button {
                    isNew = true
                    editing = Person(name: "")
                } label: {
                    Label("사람 추가", systemImage: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .navigationTitle("보낸 사람")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 90, for: .scrollContent)
        .sheet(item: $editing) { p in
            PersonEditor(person: p, isNew: isNew)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
    }
}

struct PersonEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var person: Person
    let isNew: Bool
    @State private var photoItem: PhotosPickerItem?
    /// 새 사진(저장 누를 때 반영). removePhoto면 지운다
    @State private var newPhoto: Data?
    @State private var removePhoto = false
    @State private var confirmDelete = false
    @State private var error: String?

    init(person: Person, isNew: Bool) {
        _person = State(initialValue: person)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        preview
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(hasPhoto ? "사진 바꾸기" : "사진 고르기", systemImage: "photo")
                    }
                    if hasPhoto {
                        Button("사진 지우기", role: .destructive) {
                            newPhoto = nil
                            removePhoto = true
                        }
                    }
                }
                Section {
                    TextField("이름 (알림 제목에 떠요)", text: $person.name)
                }
                Section {
                    PersonColorGrid(selection: $person.colorHex)
                } header: {
                    Text("카드 색")
                } footer: {
                    Text("이 사람을 고르면 잠금화면 카드와 다이내믹 아일랜드가 이 색으로 바뀌어요.")
                }
                Section {
                    NavigationLink {
                        PersonToneView(person: $person)
                    } label: {
                        LabeledContent("말투", value: PersonToneView.label(person, settings: store.settings))
                    }
                } footer: {
                    Text("이 사람이 보낼 때 쓸 말투예요. 바꾼 뒤 저장을 눌러야 반영돼요.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if !isNew {
                    Section {
                        Button("이 사람 삭제", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "사람 추가" : "사람 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.fontWeight(.semibold)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let jpeg = AvatarImage.prepare(data) {
                        newPhoto = jpeg
                        removePhoto = false
                    } else {
                        error = "사진을 불러오지 못했어요. 다른 사진으로 해보세요."
                    }
                    photoItem = nil
                }
            }
            .confirmationDialog("\(person.name)을(를) 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제하기", role: .destructive) {
                    store.deletePerson(person)
                    dismiss()
                }
            }
        }
    }

    private var hasPhoto: Bool {
        newPhoto != nil || (!removePhoto && store.hasAvatar(person.id))
    }

    @ViewBuilder
    private var preview: some View {
        if let newPhoto, let image = UIImage(data: newPhoto) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if !removePhoto, let image = UIImage(contentsOfFile: Store.avatarURL(for: person.id).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.accentSoft
                Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
            }
        }
    }

    private func save() {
        var p = person
        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.name.isEmpty else { error = "이름을 입력해 주세요."; return }
        store.upsertPerson(p, makeActive: isNew || store.settings.activePersonID == p.id)
        if let newPhoto { store.setAvatar(newPhoto, for: p.id) } else if removePhoto { store.setAvatar(nil, for: p.id) }
        dismiss()
    }
}

/// 사람마다 따로 쓰는 말투 고르기 + 이 사람 전용 말투 파일 가져오기
struct PersonToneView: View {
    @EnvironmentObject var store: Store
    @Binding var person: Person
    @State private var importing = false
    @State private var notice: String?

    private let sample = ScheduleItem(id: "sample", kind: .timetable, title: "자료구조", place: "K501",
                                      time: "14:00", weekdays: [1], reminders: [30])

    static func label(_ p: Person, settings: AppSettings) -> String {
        guard let t = p.tone else { return "기본 말투 (\(defaultLabel(settings)))" }
        return t == .custom ? (settings.libraryTone(p.customToneID)?.name ?? t.label) : t.label
    }

    static func defaultLabel(_ s: AppSettings) -> String {
        s.tone == .custom ? (s.libraryTone(s.customToneID)?.name ?? s.tone.label) : s.tone.label
    }

    /// 이 사람이 보내는 걸로 가정한 설정(미리보기용)
    private var previewSettings: AppSettings {
        var s = store.settings
        if let i = s.people.firstIndex(where: { $0.id == person.id }) { s.people[i] = person } else { s.people.append(person) }
        s.activePersonID = person.id
        return s
    }

    var body: some View {
        List {
            Section("말투") {
                row(nil, "기본 말투 따라가기", sub: "설정 > 잔소리의 ‘\(Self.defaultLabel(store.settings))’")
                ForEach([NagTone.plain, .gentle, .friend, .strict]) { t in
                    row(t, t.label, sub: nil)
                }
            }

            Section {
                if store.settings.toneLibrary.isEmpty {
                    Text("보관함이 비어 있어요. 아래에서 말투 파일을 가져오세요.")
                        .font(.subheadline).foregroundStyle(Theme.faint)
                }
                ForEach(store.settings.toneLibrary) { c in
                    customRow(c)
                }
            } header: {
                Text("나만의 말투")
            }

            Section("미리보기") {
                let s = previewSettings
                ForEach([1440, 30, 10], id: \.self) { n in
                    Text("· \(ReminderOption.label(n)): " + Nag.line(settings: s, item: sample, minutesBefore: n))
                        .font(.subheadline)
                }
                Text("· 할 일 체크: " + Nag.todoLine(settings: s, period: "오늘", count: 2, seed: "preview"))
                    .font(.subheadline)
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("말투 파일 가져오기", systemImage: "square.and.arrow.down")
                }
                NavigationLink {
                    ToneLibraryView()
                } label: {
                    Label("말투 보관함 관리", systemImage: "text.bubble")
                }
            } footer: {
                Text("가져온 말투는 보관함에 쌓여서 다른 사람도 골라 쓸 수 있어요. 파일은 이 아이폰 안에만 저장돼요.")
            }
        }
        .navigationTitle(person.name.isEmpty ? "말투" : "\(person.name)의 말투")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            importTone(result)
        }
        .alert("핑", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private func row(_ t: NagTone?, _ title: String, sub: String?) -> some View {
        Button {
            person.tone = t
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.text)
                    if let sub { Text(sub).font(.caption).foregroundStyle(Theme.faint) }
                }
                Spacer()
                if person.tone == t {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func customRow(_ c: CustomTone) -> some View {
        let on = person.tone == .custom && person.customToneID == c.id
        return Button {
            person.tone = .custom
            person.customToneID = c.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).foregroundStyle(Theme.text)
                    Text("문장 \(c.count)개").font(.caption).foregroundStyle(Theme.faint)
                }
                Spacer()
                if on {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func importTone(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            notice = "파일을 열지 못했어요: \(e.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), var tone = CustomTone.decodeFile(data) else {
                notice = "말투 파일(dayline-tone)이 아니에요."
                return
            }
            if person.name.trimmingCharacters(in: .whitespaces).isEmpty, let name = tone.sender { person.name = name }
            tone.sender = nil
            let added = store.addTone(tone)
            person.tone = .custom
            person.customToneID = added.id
            notice = "‘\(added.name)’ 말투를 보관함에 넣고 이 사람 말투로 골랐어요 (문장 \(added.count)개). 저장을 눌러야 반영돼요."
        }
    }
}

/// 라벤더 계열 16색 중 하나 고르기
struct PersonColorGrid: View {
    @Binding var selection: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        let current = selection ?? PersonColor.defaultHex
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(PersonColor.all, id: \.hex) { c in
                    Button { selection = c.hex } label: {
                        Circle()
                            .fill(Color(hex: c.hex))
                            .frame(height: 30)
                            .overlay {
                                if current == c.hex {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().strokeBorder(Theme.text.opacity(current == c.hex ? 0.35 : 0), lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.name)
                }
            }
            Text(PersonColor.all.first { $0.hex == current }?.name ?? "")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 8)
    }
}
