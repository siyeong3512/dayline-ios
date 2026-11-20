import SwiftUI

/// 에브리타임식 고정 시간표: 요일 × 시간 격자. 빈 칸을 누르면 그 시간으로 수업 추가.
struct TimetableView: View {
    @EnvironmentObject var store: Store
    @Binding var sheet: EditorSheet?

    private let unit: CGFloat = 56
    private let gutter: CGFloat = 26

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
        let to = max(20, segs.map { Int((Double($0.to) / 60).rounded(.up)) }.max() ?? 20)

        Screen(title: "내 시간표", addLabel: "수업",
               onAdd: { sheet = .schedule(newClass(day: Day.weekday(Date()), minutes: 9 * 60), isNew: true) }) {
            grid(days: days, from: from, hours: to - from, segs: segs)
            Text(store.timetable.isEmpty
                 ? "빈 시간을 누르거나 수업 추가로 시간표를 채워보세요."
                 : "고정 일정 \(store.timetable.count)개 · 블록을 누르면 수정할 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func newClass(day: Int, minutes: Int) -> ScheduleItem {
        ScheduleItem(kind: .timetable, date: Day.today, time: Day.clock(minutes), duration: 75,
                     weekdays: [day], color: store.timetable.count % Palette.colors.count)
    }

    private func grid(days: [Int], from: Int, hours: Int, segs: [Segment]) -> some View {
        let todayWeekday = Day.weekday(Date())
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 32)
                ForEach(days, id: \.self) { d in
                    Text(Day.names[d])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(d == todayWeekday ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(d == todayWeekday ? Color.primary.opacity(0.05) : Color.clear)
                }
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<hours, id: \.self) { i in
                        Text("\(from + i)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                            .padding(.trailing, 5)
                            .frame(width: gutter, height: unit, alignment: .topTrailing)
                    }
                }
                ForEach(days, id: \.self) { d in
                    column(day: d, from: from, hours: hours, segs: assignLanes(segs.filter { $0.day == d }))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func column(day: Int, from: Int, hours: Int, segs: [Segment]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(0..<hours, id: \.self) { i in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: w, height: unit)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
                        }
                        .contentShape(Rectangle())
                        .offset(y: CGFloat(i) * unit)
                        .onTapGesture {
                            sheet = .schedule(newClass(day: day, minutes: (from + i) * 60), isNew: true)
                        }
                        .accessibilityLabel("\(Day.names[day])요일 \(from + i)시 고정 일정 추가")
                }
                ForEach(segs) { s in
                    block(s)
                        .frame(width: max(w / CGFloat(s.lanes) - 3, 10),
                               height: max(CGFloat(s.to - s.from) / 60 * unit - 2, 22))
                        .offset(x: w * CGFloat(s.lane) / CGFloat(s.lanes) + 1.5,
                                y: CGFloat(s.from - from * 60) / 60 * unit + 1)
                }
            }
        }
        .frame(height: CGFloat(hours) * unit)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 0.5)
        }
    }

    private func block(_ s: Segment) -> some View {
        let color = Palette.color(s.item.color)
        let range = Day.clock(s.from) + "–" + (s.to == 1440 ? "24:00" : Day.clock(s.to))
        return VStack(alignment: .leading, spacing: 2) {
            Text(s.item.title)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(3)
            if !s.item.place.isEmpty {
                Text(s.item.place).font(.system(size: 10)).lineLimit(1).opacity(0.8)
            }
            Spacer(minLength: 0)
            Text((s.continued ? "이어서 · " : "") + range)
                .font(.system(size: 9, weight: .medium))
                .opacity(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.primary)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.24)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 3)
        }
        .contentShape(Rectangle())
        .onTapGesture { sheet = .schedule(s.item, isNew: false) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: 블록 배치 (웹앱과 같은 규칙)

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
