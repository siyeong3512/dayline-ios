import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DaylineWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextUpLiveActivity()
    }
}

struct NextUpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextUpAttributes.self) { context in
            NextUpLockScreen(state: context.state, started: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            let s = context.state
            let tint = NextUpAttributes.color(s.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.kindLabel).font(.caption2).foregroundStyle(Color.secondary)
                        Text(s.title).font(.headline).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: s)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(maxWidth: 96, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.place.isEmpty ? s.timeLabel : s.timeLabel + " · " + s.place)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            } compactLeading: {
                Circle().fill(tint).frame(width: 10, height: 10)
            } compactTrailing: {
                Countdown(state: s)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "clock.fill").foregroundStyle(tint)
            }
        }
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

struct NextUpLockScreen: View {
    let state: NextUpAttributes.ContentState
    /// 시작 시각이 지나면 true (staleDate = 시작 시각)
    let started: Bool

    var body: some View {
        let tint = NextUpAttributes.color(state.colorHex)
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 5, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("UP NEXT · " + state.kindLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(state.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(state.place.isEmpty ? state.timeLabel : state.timeLabel + " · " + state.place)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if started {
                    Text("시작했어요").font(.headline).foregroundStyle(tint)
                } else {
                    Countdown(state: state)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(maxWidth: 120, alignment: .trailing)
                    Text("남음").font(.caption2).foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .padding(16)
    }
}
