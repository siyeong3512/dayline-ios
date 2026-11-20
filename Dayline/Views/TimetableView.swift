import SwiftUI

/// 고정 시간표: 요일 × 시간 격자. 빈 칸을 누르면 그 시간으로 수업 추가.
struct TimetableView: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: EditorSheet?

    private let unit: CGFloat = 50
    private let gutter: CGFloat = 24

    struct Segment: Identifiable {
        let item: ScheduleItem
        let day: Int
        let from: Int
        let to: Int
        let continued: Bool
        var lane = 0
        var lanes = 1
        var id: String { "\(item.id)-\(day)-\(continued)" }
    }

    var body: some View {
        let segs = segments()
        let weekend = segs.contains { $0.day == 0 || $0.day == 6 }
        let days = weekend ? Day.mondayFirst : [1, 2, 3, 4, 5]
        let from = min(9, segs.map { $0.from / 60 }.min() ?? 9)
        let to = max(19, segs.map { Int((Double($0.to) / 60).rounded(.up)) }.max() ?? 19)

        TimelineView(.periodic(from: .now, by: 60)) { context in
            Screen(title: "시간표", actionLabel: "수업 추가",
                   action: { sheet = .schedule(newClass(day: Day.weekday(Date()), minutes: 9 * 60), isNew: true) }) {
                grid(days: days, from: from, hours: to - from, segs: segs)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                Text(store.timetable.isEmpty ? "빈칸을 누르면 그 시간에 수업을 추가해요" : "블록을 누르면 수정할 수 있어요")
                    .font(.system(size: 13)).foregroundStyle(Theme.faint)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                Band()
                todayClasses(now: context.date)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
            }
        }
    }

    private func newClass(day: Int, minutes: Int) -> ScheduleItem {
        ScheduleItem(kind: .timetable, date: Day.today, time: Day.clock(minutes), duration: 75,
                     weekdays: [day], color: store.timetable.count % Palette.colors.count)
    }

    // MARK: 오늘 수업 목록

    private func todayClasses(now: Date) -> some View {
        let key = Day.key(now)
        let list = store.events(on: key, kind: .timetable)
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "오늘 \(Day.names[Day.weekday(now)])요일 수업", trailing: list.isEmpty ? nil : "\(list.count)개")
            if list.isEmpty {
                EmptyNote(text: "오늘은 수업이 없어요")
            } else {
                ForEach(list) { x in
                    let start = Day.at(key, x.time)
                    let end = start.addingTimeInterval(TimeInterval(x.duration * 60))
                    Button { sheet = .schedule(x, isNew: false) } label: {
                        ListRow(badge: IconBadge(text: TimeText.short(x.time), bg: Palette.soft(x.color), fg: Palette.strong(x.color)),
                                meta: x.detailLine,
                                title: x.title,
                                titleColor: end < now ? Theme.faint : Theme.text) {
                            if start > now {
                                Text(TimeText.until(start, from: now))
                                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                            } else if end > now {
                                Text("수업 중").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
                            } else {
                                Text("끝").font(.system(size: 14)).foregroundStyle(Theme.faint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 격자

    private func grid(days: [Int], from: Int, hours: Int, segs: [Segment]) -> some View {
        let todayWeekday = Day.weekday(Date())
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 30)
                ForEach(days, id: \.self) { d in
                    Text(Day.names[d])
                        .font(.system(size: 13, weight: d == todayWeekday ? .heavy : .medium))
                        .foregroundStyle(d == todayWeekday ? Theme.accent : Theme.faint)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<hours, id: \.self) { i in
                        Text("\(from + i)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.faint)
                            .padding(.trailing, 5)
                            .frame(width: gutter, height: unit, alignment: .topTrailing)
                    }
                }
                ForEach(days, id: \.self) { d in
                    column(day: d, from: from, hours: hours, segs: assignLanes(segs.filter { $0.day == d }))
                }
            }
        }
    }

    private func column(day: Int, from: Int, hours: Int, segs: [Segment]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(0..<hours, id: \.self) { i in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: w, height: unit)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                        .contentShape(Rectangle())
                        .offset(y: CGFloat(i) * unit)
                        .onTapGesture {
                            sheet = .schedule(newClass(day: day, minutes: (from + i) * 60), isNew: true)
                        }
                        .accessibilityLabel("\(Day.names[day])요일 \(from + i)시 수업 추가")
                }
                ForEach(segs) { s in
                    block(s)
                        .frame(width: max(w / CGFloat(s.lanes) - 4, 10),
                               height: max(CGFloat(s.to - s.from) / 60 * unit - 2, 22))
                        .offset(x: w * CGFloat(s.lane) / CGFloat(s.lanes) + 2,
                                y: CGFloat(s.from - from * 60) / 60 * unit + 1)
                }
            }
        }
        .frame(height: CGFloat(hours) * unit)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private func block(_ s: Segment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.item.title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(3)
            if !s.item.place.isEmpty {
                Text(s.item.place).font(.system(size: 10)).lineLimit(1).opacity(0.85)
            }
            if s.continued {
                Text("이어서").font(.system(size: 9)).opacity(0.7)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Palette.strong(s.item.color))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.soft(s.item.color)))
        .contentShape(Rectangle())
        .onTapGesture { sheet = .schedule(s.item, isNew: false) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 블록 배치

    private func segments() -> [Segment] {
        var out: [Segment] = []
        for x in store.timetable {
            for d in x.weekdays {
                let from = x.start, to = x.end
                out.append(Segment(item: x, day: d, from: from, to: min(to, 1440), continued: false))
                if to > 1440 {
                    out.append(Segment(item: x, day: (d + 1) % 7, from: 0, to: min(to - 1440, 1440), continued: true))
                }
            }
        }
        return out
    }

    /// 겹치는 수업은 같은 칸을 나눠 쓴다
    private func assignLanes(_ input: [Segment]) -> [Segment] {
        let sorted = input.sorted { $0.from != $1.from ? $0.from < $1.from : $0.to < $1.to }
        var result: [Segment] = []
        var group: [Segment] = []
        var until = -1

        func finish() {
            var ends: [Int] = []
            var placed: [Segment] = []
            for var b in group {
                if let lane = ends.firstIndex(where: { $0 <= b.from }) {
                    b.lane = lane
                    ends[lane] = b.to
                } else {
                    b.lane = ends.count
                    ends.append(b.to)
                }
                placed.append(b)
            }
            for var b in placed {
                b.lanes = max(ends.count, 1)
                result.append(b)
            }
            group = []
        }

        for b in sorted {
            if b.from >= until { finish(); until = -1 }
            group.append(b)
            until = max(until, b.to)
        }
        finish()
        return result
    }
}
