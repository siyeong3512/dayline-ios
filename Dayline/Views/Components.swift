import SwiftUI

// MARK: - 화면 틀 (토스 결: 흰 배경, 굵은 제목, 오른쪽 연한 버튼)

struct Screen<Content: View>: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 25.5, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 12)
                    if let action {
                        SoftButton(title: actionLabel ?? "추가", action: action)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)
                content
            }
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Theme.screen.ignoresSafeArea())
    }
}

/// 카드 사이 간격
struct Band: View {
    var body: some View {
        Color.clear.frame(height: 12)
    }
}

extension View {
    /// 토스식 둥근 카드 (화면 양옆 12, 안쪽 20)
    func card(vertical: CGFloat = 20, horizontal: CGFloat = 20) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .padding(.horizontal, 12)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(.system(size: 18.5, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.faint)
            }
        }
    }
}

/// 연보라 바탕 + 진한 보라 글씨 버튼 ("자세히", "수업 추가")
struct SoftButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.accentStrong)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentSoft))
        }
        .buttonStyle(PressStyle())
    }
}

/// 눌렀을 때 살짝 작아지는 토스식 반응
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 목록 앞 동그란 아이콘
struct IconBadge: View {
    var text: String?
    var systemImage: String?
    let bg: Color
    let fg: Color
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(bg)
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: size * 0.42, weight: .semibold))
            } else if let text {
                Text(text)
                    .font(.system(size: text.count > 2 ? 12.5 : 15, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .foregroundStyle(fg)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 토스 목록 한 줄: 아이콘 · (회색 설명 / 굵은 제목) · 오른쪽
struct ListRow<Trailing: View>: View {
    let badge: IconBadge
    let meta: String
    let title: String
    var titleColor: Color = Theme.text
    var strike = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(meta).font(.system(size: 13.5)).foregroundStyle(Theme.faint).lineLimit(1)
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .strikethrough(strike, color: Theme.faint)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.tabIdle)
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14.5))
            .foregroundStyle(Theme.faint)
            .padding(.vertical, 12)
    }
}

// MARK: - 하단 탭바 (토스 결: 흰 바, 위쪽만 둥글게, 선택한 탭만 진하게)

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
        case .timetable: return "tablecells.fill"
        case .calendar: return "calendar"
        case .settings: return "gearshape.fill"
        }
    }
}

struct TabBar: View {
    @Environment(\.colorScheme) private var scheme
    let selected: Tab
    let onSelect: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                let on = selected == t
                Button {
                    if !on { onSelect(t) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 21, weight: .semibold))
                        Text(t.label).font(.system(size: 11, weight: on ? .bold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(on ? Theme.text : Theme.tabIdle)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(Theme.tabBar)
                // 밝은 화면은 옅은 그림자, 어두운 화면은 그림자 대신 얇은 선으로 구분
                .shadow(color: Color.black.opacity(scheme == .dark ? 0 : 0.07), radius: 12, y: -2)
                .overlay(alignment: .top) {
                    if scheme == .dark {
                        UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - 편집 화면 선택 칩

struct WeekdayPicker: View {
    @Binding var selection: [Int]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Day.mondayFirst, id: \.self) { d in
                let on = selection.contains(d)
                Button {
                    if on { selection.removeAll { $0 == d } } else { selection.append(d); selection.sort() }
                } label: {
                    Text(Day.names[d])
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(on ? Color.white : Theme.pillText)
                        .background(Circle().fill(on ? Theme.accent : Theme.pill))
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
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Color.white : Theme.pillText)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.accent : Theme.pill))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ColorGrid: View {
    @Binding var selection: Int
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
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
                        .overlay(Circle().strokeBorder(Theme.text.opacity(selection == i ? 0.35 : 0), lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Palette.names[i])
            }
        }
        .padding(.vertical, 8)
    }
}
