import SwiftUI

enum CalMode: String, CaseIterable, Identifiable {
    case day = "하루", week = "주간", month = "월간"
    var id: String { rawValue }
}

/// 약속(시작 시간만 있는 일정) 캘린더. 날짜 줄과 틀은 그대로 두고, 아래 일정 페이지만 옆으로 넘어간다.
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
        Screen(title: "내 일정", addLabel: "약속",
               onAdd: { sheet = .schedule(ScheduleItem(kind: .event, date: selected, time: "12:00",
                                                        color: 0, reminders: [60]), isNew: true) }) {
            header
            modePicker
            if mode == .month { monthGrid } else { dateStrip }
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

    private var header: some View {
        HStack(spacing: 8) {
            Text(Day.format(Day.date(selected), "yMMMM")).font(.title3.bold())
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("이전 기간")
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("다음 기간")
            Button("오늘") { select(Day.today) }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .font(.headline)
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(CalMode.allCases) { m in
                Button {
                    mode = m
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { modeIndicator = m }
                } label: {
                    Text(m.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(modeIndicator == m ? Color.primary : Color.secondary)
                        .background {
                            if modeIndicator == m {
                                Capsule().fill(Color(.secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "mode", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: 날짜 줄 / 월간 격자

    private var dateStrip: some View {
        let today = Day.today
        return HStack(spacing: 6) {
            ForEach(Day.week(selected), id: \.self) { d in
                let key = Day.key(d)
                let isSelected = key == selected
                Button { select(key) } label: {
                    VStack(spacing: 4) {
                        Text(Day.names[Day.weekday(d)]).font(.caption2.weight(.semibold))
                        Text("\(Day.cal.component(.day, from: d))").font(.headline)
                        Circle()
                            .fill(store.events(on: key).isEmpty ? Color.clear
                                  : (isSelected ? Color(.systemBackground) : Palette.color(0)))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(isSelected ? Color(.systemBackground)
                                     : (key == today ? Palette.color(0) : Color.primary))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.primary : Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Day.format(d, "MMMMdEEEE"))
            }
        }
    }

    private var monthGrid: some View {
        let base = Day.date(selected)
        let today = Day.today
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return Card(padding: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Day.mondayFirst, id: \.self) { n in
                        Text(Day.names[n]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Day.monthCells(selected), id: \.self) { d in
                        let key = Day.key(d)
                        let list = store.events(on: key)
                        let isSelected = key == selected
                        Button { select(key) } label: {
                            VStack(spacing: 3) {
                                Text("\(Day.cal.component(.day, from: d))")
                                    .font(.subheadline.weight(key == today ? .heavy : .medium))
                                    .foregroundStyle(isSelected ? Color(.systemBackground)
                                                     : key == today ? Palette.color(0) : Color.primary)
                                HStack(spacing: 2) {
                                    ForEach(list.prefix(3)) { x in
                                        Circle().fill(Palette.color(x.color)).frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 4)
                                Text(list.first?.title ?? " ")
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                    .foregroundStyle(isSelected ? Color(.systemBackground) : Color.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.primary : Color.clear))
                            .opacity(Day.sameMonth(d, base) ? 1 : 0.35)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Day.format(d, "MMMMd")), 일정 \(list.count)개")
                    }
                }
            }
        }
    }

    // MARK: 일정 페이지

    private var page: some View {
        let isWeek = mode == .week
        let days = Day.week(selected)
        let count = isWeek ? days.reduce(0) { $0 + store.events(on: Day.key($1)).count } : store.events(on: selected).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(isWeek ? "이번 주 약속" : Day.format(Day.date(selected), "MMMMdEEEE")).font(.title3.bold())
                Spacer()
                Text("\(count)개의 일정").font(.footnote).foregroundStyle(.secondary)
            }
            if isWeek {
                ForEach(days, id: \.self) { d in
                    let key = Day.key(d)
                    let list = store.events(on: key)
                    Text(Day.format(d, "MMMMdEEEE")).font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary).padding(.top, 4)
                    if list.isEmpty {
                        Text("등록된 약속이 없어요.").font(.footnote).foregroundStyle(.tertiary)
                    } else {
                        ForEach(list) { x in EventRow(item: x) { sheet = .schedule(x, isNew: false) } }
                    }
                }
            } else {
                let list = store.events(on: selected)
                if list.isEmpty {
                    Card {
                        VStack(spacing: 8) {
                            Image(systemName: "sun.haze").font(.largeTitle).foregroundStyle(.tertiary)
                            Text("여유로운 하루예요").font(.headline)
                            Text("고정 일정은 시간표에서 볼 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                            Button("약속 추가하기") {
                                sheet = .schedule(ScheduleItem(kind: .event, date: selected, time: "12:00",
                                                               reminders: [60]), isNew: true)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                } else {
                    ForEach(list) { x in EventRow(item: x) { sheet = .schedule(x, isNew: false) } }
                }
            }
        }
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
                let isSwipe = abs(dx) >= 50 && abs(dx) > abs(dy) * 1.5
                if isSwipe {
                    drag = 0
                    move(dx < 0 ? 1 : -1)
                } else {
                    withAnimation(.snappy(duration: 0.18)) { drag = 0 }
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
        // 방향을 먼저 반영한 뒤 페이지를 바꿔야 나가는 페이지도 올바른 쪽으로 빠진다
        direction = key > selected ? 1 : -1
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) { selected = key }
        }
    }
}

struct EventRow: View {
    let item: ScheduleItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.time)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
                    .padding(.top, 14)
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.color(item.color)).frame(width: 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline).foregroundStyle(Color.primary)
                        Text(item.detailLine).font(.footnote).foregroundStyle(.secondary)
                        Text(item.reminders.isEmpty ? "알림 없음"
                             : "🔔 " + item.reminders.map(ReminderOption.label).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    Spacer(minLength: 0)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.color(item.color).opacity(0.1)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }
}
