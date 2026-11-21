import SwiftUI
import UniformTypeIdentifiers

/// 말투 보관함: 말투 파일을 여러 개 가져오고, 이름 바꾸고, 지운다.
struct ToneLibraryView: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    @State private var notice: String?
    @State private var renaming: CustomTone?
    @State private var newName = ""
    @State private var deleting: CustomTone?

    var body: some View {
        List {
            Section {
                if store.settings.toneLibrary.isEmpty {
                    Text("아직 가져온 말투가 없어요.")
                        .font(.subheadline).foregroundStyle(Theme.faint)
                }
                ForEach(store.settings.toneLibrary) { t in
                    let users = store.toneUsers(t.id)
                    HStack(spacing: 12) {
                        IconBadge(systemImage: "text.bubble.fill", bg: Theme.accentSoft, fg: Theme.accent, size: 38)
                        VStack(alignment: .leading, spacing: 2.5) {
                            Text(t.name).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("문장 \(t.count)개" + (users.isEmpty ? "" : " · " + users.joined(separator: ", ") + "에서 쓰는 중"))
                                .font(.system(size: 13)).foregroundStyle(Theme.faint)
                                .lineLimit(1)
                        }
                        Spacer()
                        Menu {
                            Button("이름 바꾸기", systemImage: "pencil") {
                                newName = t.name
                                renaming = t
                            }
                            Button("삭제", systemImage: "trash", role: .destructive) { deleting = t }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .swipeActions {
                        Button("삭제", role: .destructive) { deleting = t }
                    }
                }
            } footer: {
                Text("같은 이름의 말투를 다시 가져오면 문장만 새것으로 바뀌고, 쓰던 곳은 그대로예요. 지우면 그 말투를 쓰던 곳은 기본 말투로 돌아가요.")
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("말투 파일 가져오기 (여러 개 선택 가능)", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle("말투 보관함")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("말투 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $newName)
            Button("취소", role: .cancel) {}
            Button("저장") { if let t = renaming { store.renameTone(t.id, to: newName) } }
        }
        .confirmationDialog("‘\(deleting?.name ?? "")’ 말투를 지울까요?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("삭제하기", role: .destructive) { if let t = deleting { store.deleteTone(t.id) } }
        }
        .alert("핑", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            notice = "파일을 열지 못했어요: \(e.localizedDescription)"
        case .success(let urls):
            var added: [String] = []
            var failed = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let tone = CustomTone.decodeFile(data) {
                    added.append(store.addTone(tone).name)
                } else {
                    failed += 1
                }
            }
            var msg = added.isEmpty ? "" : "‘" + added.joined(separator: "’, ‘") + "’ 말투를 넣었어요."
            if failed > 0 { msg += (msg.isEmpty ? "" : " ") + "말투 파일이 아닌 \(failed)개는 건너뛰었어요." }
            notice = msg
        }
    }
}
