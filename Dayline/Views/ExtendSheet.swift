import SwiftUI

/// 잠금화면 카드에서 '못 했어'를 누르면 열리는 화면: 얼마나 연장할지 고른다.
struct ExtendRequest: Identifiable {
    let itemID: String
    let start: Date
    var id: String { ResultLog.key(itemID, start) }

    /// pingapp://extend?id=...&start=...
    init?(url: URL) {
        guard url.scheme == "pingapp", url.host == "extend",
              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = q.first(where: { $0.name == "id" })?.value,
              let raw = q.first(where: { $0.name == "start" })?.value, let t = Double(raw) else { return nil }
        itemID = id
        start = Date(timeIntervalSince1970: t)
    }
}

struct ExtendSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let request: ExtendRequest

    private let options = [10, 30, 60, 120]

    var body: some View {
        let item = store.items.first { $0.id == request.itemID }
        VStack(alignment: .leading, spacing: 0) {
            Text("얼마나 더 필요해?")
                .font(.system(size: 22.5, weight: .bold))
                .foregroundStyle(Theme.text)
            Text((item?.title ?? "일정") + " · 연장하면 그 시간에 다시 물어볼게요")
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.sub)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(options, id: \.self) { m in
                    Button {
                        store.extend(itemID: request.itemID, start: request.start, minutes: m)
                        dismiss()
                    } label: {
                        Text(ReminderOption.amount(m) + " 더")
                            .font(.system(size: 16.5, weight: .bold))
                            .foregroundStyle(Theme.accentStrong)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accentSoft))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.top, 24)

            Button {
                store.giveUp(itemID: request.itemID, start: request.start)
                dismiss()
            } label: {
                Text("오늘은 그만할래")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(PressStyle())
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .presentationDetents([.height(330)])
        .presentationCornerRadius(28)
    }
}
