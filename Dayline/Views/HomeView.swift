import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: EditorSheet?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let key = Day.key(context.date)
            Screen(title: Day.format(context.date, "MMMMdEEEE"), actionLabel: "할 일 추가",
                   action: { sheet = .todo(TodoItem(cadence: .daily), isNew: true) }) {
                nextUp(context.date)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                Band()
                todoSection(key)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                Band()
                todaySection(key, now: context.date)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
            }
        }
    }

    // MARK: 다음 일정

    @ViewBuilder
    private func nextUp(_ now: Date) -> some View {
        if let next = store.upNext(now: now) {
            HStack(spacing: 14) {
                IconBadge(systemImage: "clock.fill", bg: Theme.accentSoft, fg: Theme.accent, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeText.until(next.when, from: now) + (next.item.place.isEmpty ? "" : " · " + next.item.place))
                        .font(.system(size: 14)).foregroundStyle(Theme.sub)
                    Text(next.item.title)
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SoftButton(title: "자세히") { sheet = .schedule(next.item, isNew: false) }
            }
        } else {
            HStack(spacing: 14) {
                IconBadge(systemImage: "sun.max.fill", bg: Theme.pill, fg: Theme.faint, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("다가오는 일정").font(.system(size: 14)).foregroundStyle(Theme.sub)
                    Text("여유로운 하루예요").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                }
            }
        }
    }

    // MARK: 할 일

    private func todoSection(_ key: String) -> some View {
        let active = store.todos.filter { !$0.archived }
        let done = active.filter { $0.isDone(on: key) }.count
        let tasks = store.activeTodos(filter: nil, on: key)
        let progress = active.isEmpty ? 0 : CGFloat(done) / CGFloat(active.count)
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "오늘의 할 일", trailing: active.isEmpty ? nil : "\(active.count)개 중 \(done)개")
            if !active.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.pill)
                        Capsule().fill(Theme.accent).frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0))
                    }
                }
                .frame(height: 6)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .animation(.easeOut(duration: 0.45), value: progress)
            }
            if tasks.isEmpty {
                EmptyNote(text: "할 일을 추가하고 하나씩 체크해 보세요")
            } else {
                ForEach(tasks) { task in
                    TodoRow(task: task, dayKey: key,
                            onToggle: { withAnimation(.snappy) { store.toggle(task, on: key) } },
                            onEdit: { sheet = .todo(task, isNew: false) })
                }
            }
        }
    }

    // MARK: 오늘 일정 (수업 + 약속)

    private func todaySection(_ key: String, now: Date) -> some View {
        let list = (store.events(on: key, kind: .timetable) + store.events(on: key, kind: .event))
            .sorted { $0.time < $1.time }
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "오늘 일정", trailing: list.isEmpty ? nil : "\(list.count)개")
            if list.isEmpty {
                EmptyNote(text: "오늘은 일정이 없어요")
            } else {
                ForEach(list) { x in
                    Button { sheet = .schedule(x, isNew: false) } label: {
                        ListRow(badge: IconBadge(text: TimeText.short(x.time), bg: Palette.soft(x.color), fg: Palette.strong(x.color)),
                                meta: (x.kind == .timetable ? "수업 · " : "약속 · ") + TimeText.ampm(x.time) + (x.place.isEmpty ? "" : " · " + x.place),
                                title: x.title,
                                titleColor: Day.at(key, x.time) < now ? Theme.faint : Theme.text) {
                            Chevron()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TodoRow: View {
    let task: TodoItem
    let dayKey: String
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let done = task.isDone(on: dayKey)
        HStack(spacing: 14) {
            Button(action: onEdit) {
                ListRow(badge: IconBadge(text: badgeText,
                                         bg: done ? Theme.pill : badgeBg,
                                         fg: done ? Theme.tabIdle : badgeFg),
                        meta: meta,
                        title: task.title,
                        titleColor: done ? Theme.faint : Theme.text,
                        strike: done) { EmptyView() }
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                Text(done ? "완료" : "체크")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(done ? Color.white : Theme.pillText)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(done ? Theme.accent : Theme.pill))
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.success, trigger: done) { _, new in new }
            .accessibilityLabel("\(task.title) 완료")
            .accessibilityAddTraits(done ? .isSelected : [])
        }
    }

    private var badgeText: String {
        switch task.cadence {
        case .daily: return "D"
        case .weekly: return "W"
        case .monthly: return "M"
        }
    }

    private var badgeBg: Color {
        switch task.cadence {
        case .daily: return Theme.accentSoft
        case .weekly: return Palette.soft(3)
        case .monthly: return Palette.soft(2)
        }
    }

    private var badgeFg: Color {
        switch task.cadence {
        case .daily: return Theme.accentStrong
        case .weekly: return Palette.strong(3)
        case .monthly: return Palette.strong(2)
        }
    }

    private var meta: String {
        var s = task.cadence.korean
        if let due = task.dueKey(on: dayKey) {
            let delta = Day.cal.dateComponents([.day], from: Day.date(dayKey), to: Day.date(due)).day ?? 0
            if delta < 0 { s += " · 기한 지남" }
            else if delta == 0 { s += " · 오늘 마감" }
            else if delta == 1 { s += " · 내일 마감" }
            else { s += " · " + Day.format(Day.date(due), "MdE") + " 마감" }
        }
        return s
    }
}
