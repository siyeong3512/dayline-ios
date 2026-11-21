import SwiftUI

enum CalMode: String, CaseIterable, Identifiable {
    case day = "하루", week = "주간", month = "월간"
    var id: String { rawValue }
}

/// 약속 캘린더. 날짜 줄과 틀은 그대로 두고, 아래 일정 페이지만 옆으로 넘어간다.
struct CalendarScreen: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: EditorSheet?
    @State private var mode: CalMode = .day
    @State private var modeIndicator: CalMode = .day
    @State private var selected = Day.today
    @State private var direction = 1
    @State private var drag: CGFloat = 0
    @Namespace private var ns

    var body: some View {
        Screen(title: Day.format(Day.date(selected), "MMMM") + " 일정", actionLabel: "약속 추가",
               action: { sheet = .schedule(ScheduleItem(kind: .event, date: selected, time: "12:00", reminders: [60]), isNew: true) }) {
            VStack(alignment: .leading, spacing: 16) {
                controls
                modePicker
                if mode == .month { monthGrid } else { dateStrip }
            }
            .card()
            Band()
            ZStack(alignment: .topLeading) {
                page
                    .id(pageKey)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction > 0 ? .trailing : .leading),
                        removal: .move(edge: direction > 0 ? .leading : .trailing)))
                    .offset(x: drag)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
        }
        .simultaneousGesture(swipe)
    }

    private var pageKey: String {
        mode == .week ? "w" + Day.key(Day.weekStart(Day.date(selected))) : mode.rawValue + selected
    }

    // MARK: 머리글

    private var controls: some View {
        HStack(spacing: 8) {
            Text(Day.format(Day.date(selected), "y년"))
                .font(.system(size: 15)).foregroundStyle(Theme.sub)
            Spacer()
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .accessibilityLabel("이전 기간")
            Button { move(1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .accessibilityLabel("다음 기간")
            Button { select(Day.today) } label: {
                Text("오늘")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.pillText)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.pill))
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.sub)
        .buttonStyle(.plain)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(CalMode.allCases) { m in
                let on = modeIndicator == m
                Button {
                    mode = m
                    withAnimation(.easeOut(duration: 0.24)) { modeIndicator = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 15, weight: on ? .bold : .medium))
                        .foregroundStyle(on ? Theme.text : Theme.sub)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Theme.bg)
                                    .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "mode", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.band))
    }

    // MARK: 날짜 줄 / 월간 격자

    private var dateStrip: some View {
        let today = Day.today
        return HStack(spacing: 2) {
            ForEach(Day.week(selected), id: \.self) { d in
                let key = Day.key(d)
                let on = key == selected
                let has = !store.events(on: key).isEmpty
                Button { select(key) } label: {
                    VStack(spacing: 8) {
                        Text(Day.names[Day.weekday(d)])
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(on || key == today ? Theme.accent : Theme.faint)
                        Text("\(Day.cal.component(.day, from: d))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(on ? Color.white : (key == today ? Theme.accent : Theme.text))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(on ? Theme.accent : Color.clear))
                        Circle()
                            .fill(has && !on ? Theme.tabIdle : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Day.format(d, "MMMMdEEEE"))
            }
        }
    }

    private var monthGrid: some View {
        let base = Day.date(selected)
        let today = Day.today
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Day.mondayFirst, id: \.self) { n in
                    Text(Day.names[n]).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Day.monthCells(selected), id: \.self) { d in
                    let key = Day.key(d)
                    let list = store.events(on: key)
                    let on = key == selected
                    Button { select(key) } label: {
                        VStack(spacing: 4) {
                            Text("\(Day.cal.component(.day, from: d))")
                                .font(.system(size: 15, weight: key == today || on ? .bold : .medium))
                                .foregroundStyle(on ? Color.white : (key == today ? Theme.accent : Theme.text))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(on ? Theme.accent : Color.clear))
                            HStack(spacing: 2) {
                                ForEach(list.prefix(3)) { x in
                                    Circle().fill(Palette.color(x.color)).frame(width: 4, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .opacity(Day.sameMonth(d, base) ? 1 : 0.3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Day.format(d, "MMMMd")), 약속 \(list.count)개")
                }
            }
        }
    }

    // MARK: 일정 페이지

    private var page: some View {
        let isWeek = mode == .week
        let days = Day.week(selected)
        let count = isWeek ? days.reduce(0) { $0 + store.events(on: Day.key($1)).count } : store.events(on: selected).count
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: isWeek ? "이번 주 약속" : Day.format(Day.date(selected), "dEEEE"),
                          trailing: count == 0 ? nil : "\(count)개")
            if isWeek {
                ForEach(days, id: \.self) { d in
                    let key = Day.key(d)
                    let list = store.events(on: key)
                    if !list.isEmpty {
                        Text(Day.format(d, "MMMMdEEEE"))
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.faint)
                            .padding(.top, 12)
                        ForEach(list) { x in EventRow(item: x) { sheet = .schedule(x, isNew: false) } }
                    }
                }
                if count == 0 { EmptyNote(text: "이번 주는 약속이 없어요") }
            } else {
                let list = store.events(on: selected)
                if list.isEmpty {
                    EmptyNote(text: "약속이 없어요. 고정 수업은 시간표 탭에서 볼 수 있어요")
                } else {
                    ForEach(list) { x in EventRow(item: x) { sheet = .schedule(x, isNew: false) } }
                }
            }
        }
        .card()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: 이동

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) > 12 && abs(dx) > abs(dy) * 1.5 { drag = dx }
            }
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) >= 50 && abs(dx) > abs(dy) * 1.5 {
                    drag = 0
                    move(dx < 0 ? 1 : -1)
                } else {
                    withAnimation(.easeOut(duration: 0.18)) { drag = 0 }
                }
            }
    }

    private func move(_ delta: Int) {
        let d = Day.date(selected)
        let next: Date
        switch mode {
        case .month: next = Day.cal.date(byAdding: .month, value: delta, to: Day.firstOfMonth(d)) ?? d
        case .week: next = Day.add(d, delta * 7)
        case .day: next = Day.add(d, delta)
        }
        select(Day.key(next))
    }

    private func select(_ key: String) {
        guard key != selected else { return }
        direction = key > selected ? 1 : -1
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.28)) { selected = key }
        }
    }
}

struct EventRow: View {
    let item: ScheduleItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ListRow(badge: IconBadge(text: TimeText.short(item.time), bg: Palette.soft(item.color), fg: Palette.strong(item.color)),
                    meta: meta,
                    title: item.title) {
                Chevron()
            }
        }
        .buttonStyle(.plain)
    }

    private var meta: String {
        var s = TimeText.ampm(item.time)
        if !item.place.isEmpty { s += " · " + item.place }
        if let first = item.reminders.first { s += " · " + ReminderOption.label(first) + " 알림" }
        return s
    }
}
