import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: EditorSheet?
    @State private var filter: Cadence?
    @State private var filterIndicator: Cadence?
    @Namespace private var ns

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let key = Day.key(context.date)
            Screen(title: "오늘의 할 일", addLabel: "할 일",
                   onAdd: { sheet = .todo(TodoItem(cadence: filter ?? .daily), isNew: true) }) {
                overview(key)
                filterBar
                list(key)
                Text("Daily는 매일, Weekly는 월요일, Monthly는 매월 1일에 새 체크리스트로 시작해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func overview(_ key: String) -> some View {
        let active = store.todos.filter { !$0.archived }
        let done = active.filter { $0.isDone(on: key) }.count
        let value = active.isEmpty ? 0 : Double(done) / Double(active.count)
        return Card {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "TODAY’S FOCUS")
                    Text(Day.format(Day.date(key), "MMMMdEEEE")).font(.title3.bold())
                    Text(active.isEmpty ? "작은 할 일부터 하나씩 시작해요." : "\(active.count)개 중 \(done)개 완료")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                ProgressRing(value: value)
            }
        }
    }

    private var filterBar: some View {
        let options: [Cadence?] = [nil, .daily, .weekly, .monthly]
        return HStack(spacing: 0) {
            ForEach(options, id: \.self) { c in
                Button {
                    filter = c
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { filterIndicator = c }
                } label: {
                    Text(c?.label ?? "전체")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(filterIndicator == c ? Color.primary : Color.secondary)
                        .background {
                            if filterIndicator == c {
                                Capsule().fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "filter", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private func list(_ key: String) -> some View {
        let tasks = store.activeTodos(filter: filter, on: key)
        if tasks.isEmpty {
            Card {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(store.todos.contains(where: { !$0.archived }) ? "이 주기의 할 일이 없어요" : "오늘의 작은 시작")
                        .font(.headline)
                    Text("할 일을 적고, 하나씩 체크해보세요.").font(.footnote).foregroundStyle(.secondary)
                    Button("할 일 추가하기") { sheet = .todo(TodoItem(cadence: filter ?? .daily), isNew: true) }
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    TodoRow(task: task, dayKey: key,
                            onToggle: { withAnimation(.snappy) { store.toggle(task, on: key) } },
                            onEdit: { sheet = .todo(task, isNew: false) })
                }
            }
        }
    }
}

struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(value, 0.0001))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(value > 0 ? 1 : 0)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: value))
        }
        .frame(width: 74, height: 74)
        .animation(.easeOut(duration: 0.52), value: value)
        .accessibilityElement()
        .accessibilityLabel("할 일 완료율")
        .accessibilityValue("\(Int((value * 100).rounded()))퍼센트")
    }
}

struct TodoRow: View {
    let task: TodoItem
    let dayKey: String
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let done = task.isDone(on: dayKey)
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.primary : Color.secondary.opacity(0.5), lineWidth: 2)
                        .background(Circle().fill(done ? Color.primary : Color.clear))
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color(.systemBackground))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: done) { _, new in new }
            .accessibilityLabel("\(task.title) 완료")
            .accessibilityAddTraits(done ? .isSelected : [])

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(task.cadence.label)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(task.cadence.tint.opacity(0.16)))
                            .foregroundStyle(task.cadence.tint)
                        if let label = dueLabel {
                            Text(label.text)
                                .font(.caption)
                                .foregroundStyle(label.overdue ? Color.red : Color.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "ellipsis").foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .opacity(done ? 0.75 : 1)
    }

    private var dueLabel: (text: String, overdue: Bool)? {
        guard let due = task.dueKey(on: dayKey) else { return nil }
        let delta = Day.cal.dateComponents([.day], from: Day.date(dayKey), to: Day.date(due)).day ?? 0
        if delta < 0 { return ("기한 지남", true) }
        if delta == 0 { return ("오늘 마감", false) }
        if delta == 1 { return ("내일 마감", false) }
        return (Day.format(Day.date(due), "Md") + " 마감", false)
    }
}
