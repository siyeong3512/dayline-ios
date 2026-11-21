import SwiftUI

/// 설정 > 사이버캠퍼스: 학번·비밀번호를 키체인에 넣고 과제·시험 마감을 자동으로 가져온다
struct CyberCampusSection: View {
    @EnvironmentObject var store: Store
    @State private var connected = CyberCampus.isConnected
    @State private var userID = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDisconnect = false

    var body: some View {
        Section {
            if connected {
                LabeledContent("마지막 동기화", value: lastLabel)
                if let m = message ?? CyberCampus.lastMessage {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    run { try await CyberCampus.sync(store: store) }
                } label: {
                    HStack {
                        Text("지금 가져오기")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
                Button("연결 해제", role: .destructive) { confirmDisconnect = true }
            } else {
                TextField("학번(아이디)", text: $userID)
                    .textContentType(.username)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("비밀번호", text: $password)
                    .textContentType(.password)
                Button {
                    let id = userID.trimmingCharacters(in: .whitespaces), pw = password
                    CyberCampus.connect(id: id, password: pw)
                    run {
                        do {
                            let n = try await CyberCampus.sync(store: store)
                            connected = true
                            password = ""
                            CyberCampus.scheduleBackground()
                            return n
                        } catch {
                            CyberCampus.disconnect()
                            throw error
                        }
                    }
                } label: {
                    HStack {
                        Text("연결하기")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || userID.isEmpty || password.isEmpty)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        } header: {
            Text("서강대 사이버캠퍼스")
        } footer: {
            Text("과제·팀과제·퀴즈·중간시험·기말시험 마감을 약속으로 가져와요(하루 전·3시간 전·1시간 전 알림). 앱을 열 때와 백그라운드에서 자동으로 확인하고, 제출해서 목록에서 사라지면 핑에서도 지워요. 가져온 일정을 지우면 다시 넣지 않아요. 학번·비밀번호는 이 아이폰의 키체인에만 저장되고, 로그인이 풀리면 그 값으로 다시 로그인해요.")
        }
        .confirmationDialog("사이버캠퍼스 연결을 해제할까요?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("연결 해제", role: .destructive) {
                CyberCampus.disconnect()
                connected = false
                message = nil
            }
        } message: {
            Text("저장된 학번·비밀번호를 지워요. 이미 가져온 일정은 그대로 남아요.")
        }
    }

    private var lastLabel: String {
        guard let d = CyberCampus.lastSync else { return "아직 없음" }
        return Day.format(d, "MMMdEjm")
    }

    private func run(_ work: @escaping () async throws -> Int) {
        busy = true
        message = nil
        Task { @MainActor in
            do {
                let n = try await work()
                message = "과제·시험 \(n)개를 확인했어요."
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}
