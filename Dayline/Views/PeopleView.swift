import PhotosUI
import SwiftUI

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
                    HStack(spacing: 14) {
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
                    HStack(spacing: 14) {
                        Button {
                            store.setActivePerson(p.id)
                        } label: {
                            HStack(spacing: 14) {
                                AvatarView(personID: p.id, version: store.avatarVersion, size: 44)
                                    .overlay(Circle().strokeBorder(store.settings.activePersonID == p.id ? Theme.accent : Color.clear, lineWidth: 2))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
                                    Text(store.hasAvatar(p.id) ? "사진 있음" : "사진 없음")
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
