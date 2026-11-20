import SwiftUI

// MARK: - 화면 공통 틀: 브랜드 · 제목 · 추가 버튼 · UP NEXT

struct Screen<Content: View>: View {
    let title: String
    var addLabel: String?
    var onAdd: (() -> Void)?
    var showsNext = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Brand()
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                    if let onAdd {
                        Button(action: onAdd) {
                            Label(addLabel ?? "추가", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .foregroundStyle(Color(.systemBackground))
                                .background(Capsule().fill(Color.primary))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if showsNext { UpNextCard() }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

struct Brand: View {
    var body: some View {
        (Text("dayline").foregroundColor(.primary) + Text(".").foregroundColor(Palette.color(0)))
            .font(.system(size: 17, weight: .heavy, design: .rounded))
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - UP NEXT

struct UpNextCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Card {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "UP NEXT")
                        if let next = store.upNext(now: context.date) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(next.item.title).font(.headline)
                                Text(Self.countdown(from: context.date, to: next.when))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Palette.color(next.item.color).opacity(0.18)))
                                    .foregroundStyle(Palette.color(next.item.color))
                            }
                            Text(Self.detail(next.item, next.when))
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("다음 일정을 위한 여유.").font(.headline)
                            Text("다가오는 일정이 없어요.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    static func countdown(from now: Date, to when: Date) -> String {
        let m = Int((when.timeIntervalSince(now) / 60).rounded(.up))
        if m < 60 { return "\(max(m, 0))분 후" }
        if m < 1440 { return "\(m / 60)시간 \(m % 60)분 후" }
        return "\(m / 1440)일 후"
    }

    static func detail(_ x: ScheduleItem, _ when: Date) -> String {
        var s = (x.kind == .timetable ? "시간표" : "약속") + " · " + Day.format(when, "MMMdEEE") + " " + x.time
        if !x.place.isEmpty { s += " · " + x.place }
        return s
    }
}

// MARK: - 하단 탭바 (반투명 + 물방울처럼 옮겨가는 선택 표시)

enum Tab: String, CaseIterable, Identifiable {
    case home, timetable, calendar, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "홈"
        case .timetable: return "시간표"
        case .calendar: return "캘린더"
        case .settings: return "설정"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .timetable: return "square.grid.3x3.fill"
        case .calendar: return "calendar"
        case .settings: return "gearshape.fill"
        }
    }
}

struct TabBar: View {
    let selected: Tab
    let onSelect: (Tab) -> Void
    @Namespace private var ns
    @State private var squash = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button {
                    guard t != selected else { return }
                    onSelect(t)
                    squash = true
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5).delay(0.12)) { squash = false }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17, weight: .semibold))
                        Text(t.label).font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(selected == t ? Color.primary : Color.secondary)
                    .background {
                        if selected == t {
                            Capsule()
                                .fill(Color.primary.opacity(0.1))
                                .scaleEffect(x: squash ? 1.18 : 1, y: squash ? 0.86 : 1)
                                .matchedGeometryEffect(id: "droplet", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.label)
                .accessibilityAddTraits(selected == t ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .padding(.horizontal, 22)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - 편집기에서 쓰는 선택 칩

struct WeekdayPicker: View {
    @Binding var selection: [Int]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Day.mondayFirst, id: \.self) { d in
                let on = selection.contains(d)
                Button {
                    if on { selection.removeAll { $0 == d } } else { selection.append(d); selection.sort() }
                } label: {
                    Text(Day.names[d])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                        .background(Circle().fill(on ? Color.primary : Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ReminderChips: View {
    @Binding var selection: [Int]
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(ReminderOption.all, id: \.self) { n in
                let on = selection.contains(n)
                Button {
                    if on { selection.removeAll { $0 == n } } else { selection.append(n); selection.sort() }
                } label: {
                    Text(ReminderOption.label(n))
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(on ? Color(.systemBackground) : Color.primary)
                        .background(Capsule().fill(on ? Color.primary : Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ColorGrid: View {
    @Binding var selection: Int
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Palette.colors.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Circle()
                        .fill(Palette.colors[i])
                        .frame(height: 34)
                        .overlay {
                            if selection == i {
                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selection == i ? 0.5 : 0), lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Palette.names[i])
            }
        }
        .padding(.vertical, 6)
    }
}
