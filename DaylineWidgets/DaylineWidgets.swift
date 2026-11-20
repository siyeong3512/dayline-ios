import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct DaylineWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextUpLiveActivity()
    }
}

/// 토스 결 + 라벤더 (앱과 같은 색)
enum WidgetTheme {
    static func dynamic(_ light: UInt64, _ dark: UInt64) -> Color {
        func ui(_ v: UInt64) -> UIColor {
            UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                    blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let accent = dynamic(0x7B5CE6, 0x9D85F2)
    static let accentSoft = dynamic(0xF1ECFF, 0x2B2547)
    static let text = dynamic(0x191F28, 0xF2F3F5)
    static let sub = dynamic(0x6B7684, 0xA3A9B3)
    static let track = dynamic(0xE9E4F7, 0x2A2C32)
    static let bubble = dynamic(0xF4F1FB, 0x24262C)
}

struct NextUpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextUpAttributes.self) { context in
            NextUpLockScreen(state: context.state, started: context.isStale)
                .activitySystemActionForegroundColor(WidgetTheme.accent)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Face(state: s, size: 52)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.sender ?? s.kindLabel).font(.caption).foregroundStyle(Color.secondary)
                        Text(s.title).font(.headline).lineLimit(1)
                        Text(s.place.isEmpty ? s.timeLabel : s.timeLabel + " · " + s.place)
                            .font(.caption2).foregroundStyle(Color.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .frame(maxWidth: 84, alignment: .trailing)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Bar(state: s)
                        if let line = s.line {
                            Text(line).font(.subheadline).lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Face(state: s, size: 24)
            } compactTrailing: {
                Countdown(state: s)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.accent)
                    .frame(maxWidth: 52)
            } minimal: {
                Face(state: s, size: 24)
            }
        }
    }
}

/// 보낸 사람 얼굴(썸네일). 없으면 일정 색 동그라미에 시계.
struct Face: View {
    let state: NextUpAttributes.ContentState
    let size: CGFloat

    var body: some View {
        let tint = NextUpAttributes.color(state.colorHex)
        Group {
            if let data = state.avatar, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                tint.overlay {
                    Image(systemName: "clock.fill").font(.system(size: size * 0.42)).foregroundStyle(Color.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(WidgetTheme.accent, lineWidth: size >= 40 ? 2.5 : 1.5))
    }
}

/// 일정 시작까지 줄어드는 타이머 (iOS가 직접 갱신)
struct Countdown: View {
    let state: NextUpAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.from...max(state.from, state.start), countsDown: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// 카드를 띄운 때부터 시작 시각까지 차오르는 진행 바 (iOS가 직접 갱신)
struct Bar: View {
    let state: NextUpAttributes.ContentState

    var body: some View {
        ProgressView(timerInterval: state.from...max(state.from.addingTimeInterval(1), state.start),
                     countsDown: false,
                     label: { EmptyView() },
                     currentValueLabel: { EmptyView() })
            .progressViewStyle(.linear)
            .tint(WidgetTheme.accent)
    }
}

struct NextUpLockScreen: View {
    let state: NextUpAttributes.ContentState
    /// 시작 시각이 지나면 true (staleDate = 시작 시각)
    let started: Bool

    private var kind: String { state.kindLabel == "시간표" ? "수업" : "약속" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Face(state: state, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.sender.map { "\($0) · 다음 \(kind)" } ?? "다음 \(kind)")
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetTheme.sub)
                        .lineLimit(1)
                    Text(state.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WidgetTheme.text)
                        .lineLimit(1)
                    Text(state.place.isEmpty ? state.timeLabel : state.timeLabel + " · " + state.place)
                        .font(.system(size: 14))
                        .foregroundStyle(WidgetTheme.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    if started {
                        Text("시작했어요").font(.headline).foregroundStyle(WidgetTheme.accent)
                    } else {
                        Countdown(state: state)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(WidgetTheme.accent)
                            .frame(maxWidth: 110, alignment: .trailing)
                        Text("남음").font(.caption2).foregroundStyle(WidgetTheme.sub)
                    }
                }
            }
            if !started {
                Bar(state: state)
            }
            if let line = state.line, !started {
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WidgetTheme.bubble))
            }
        }
        .padding(16)
    }
}
