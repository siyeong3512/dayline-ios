import ActivityKit
import AppIntents
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
            NextUpLockScreen(state: context.state, started: context.isStale || context.state.start <= Date())
                .activityBackgroundTint(CardStyle.base)
                .activitySystemActionForegroundColor(CardStyle.accent(context.state))
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
                        .foregroundStyle(CardStyle.accent(s))
                        .frame(maxWidth: 84, alignment: .trailing)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let line = s.line {
                        Secret { Text(line) }
                            .font(.subheadline)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Face(state: s, size: 24)
            } compactTrailing: {
                Countdown(state: s)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CardStyle.accent(s))
                    .frame(maxWidth: 52)
            } minimal: {
                Face(state: s, size: 24)
            }
            .keylineTint(CardStyle.accent(s))
        }
    }
}


/// 보낸 사람 얼굴. 공유 폴더의 고화질 사진 → 작은 썸네일 → 일정 색 동그라미 순서로 쓴다.
struct Face: View {
    let state: NextUpAttributes.ContentState
    let size: CGFloat

    /// 다이내믹 아일랜드처럼 작은 자리는 데이터에 실린 썸네일로 충분하고,
    /// 큰 자리만 공유 폴더 사진을 '보이는 크기 그대로' 줄여서 쓴다.
    /// (큰 원본을 그대로 넘기면 메모리 제한 때문에 빈 동그라미로 그려질 수 있다)
    private var image: UIImage? {
        let pixels = CGSize(width: size * 3, height: size * 3)
        let thumb = state.avatar.flatMap { UIImage(data: $0) }
        if size < 40, let thumb { return thumb.preparingThumbnail(of: pixels) ?? thumb }
        if let key = state.avatarKey, let url = NextUpAttributes.avatarFile(key),
           let img = UIImage(contentsOfFile: url.path), let small = img.preparingThumbnail(of: pixels) {
            return small
        }
        return thumb.map { $0.preparingThumbnail(of: pixels) ?? $0 }
    }

    var body: some View {
        let tint = NextUpAttributes.color(state.colorHex)
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                tint.overlay {
                    Image(systemName: "clock.fill").font(.system(size: size * 0.42)).foregroundStyle(Color.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(CardStyle.accent(state), lineWidth: size >= 40 ? 2 : 1.5))
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

/// 잠금화면 카드 색 (밝은/어두운 모드 상관없이 같은 짙은 라벤더 카드)
enum CardStyle {
    static func hex(_ v: UInt64, _ a: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
              blue: Double(v & 0xff) / 255, opacity: a)
    }
    static let base = hex(0x16131F)
    static let text = hex(0xF7F5FF)
    static let sub = hex(0xA9A3BD)
    static let bubble = Color.white.opacity(0.08)

    /// 보낸 사람 색 (rgb 0~1)
    private static func rgb(_ s: NextUpAttributes.ContentState) -> (Double, Double, Double) {
        let v = UInt64(s.accentHex ?? "7B5CE6", radix: 16) ?? 0x7B5CE6
        return (Double((v >> 16) & 0xff) / 255, Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }

    /// 색을 흰색(t>0) 또는 검정(t<0) 쪽으로 섞는다
    private static func mix(_ s: NextUpAttributes.ContentState, _ t: Double, _ a: Double = 1) -> Color {
        let (r, g, b) = rgb(s)
        func f(_ c: Double) -> Double { t >= 0 ? c + (1 - c) * t : c * (1 + t) }
        return Color(red: f(r), green: f(g), blue: f(b), opacity: a)
    }

    /// 짙은 카드 위에서 잘 보이게 밝힌 글씨·숫자 색
    static func accent(_ s: NextUpAttributes.ContentState) -> Color { mix(s, 0.38) }

    /// 끼어든 사람 색 (같은 방식으로 밝힘)
    static func accent(hex: String?) -> Color {
        let v = UInt64(hex ?? "7B5CE6", radix: 16) ?? 0x7B5CE6
        func f(_ c: UInt64) -> Double { let x = Double(c & 0xff) / 255; return x + (1 - x) * 0.38 }
        return Color(red: f(v >> 16), green: f(v >> 8), blue: f(v))
    }

    static func background(_ s: NextUpAttributes.ContentState) -> some View {
        ZStack {
            LinearGradient(colors: [mix(s, -0.62), mix(s, -0.82), hex(0x100E17)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [mix(s, 0.05, 0.42), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 190)
        }
    }
}

struct NextUpLockScreen: View {
    let state: NextUpAttributes.ContentState
    /// 시작 시각이 지났으면 true
    let started: Bool

    /// 1시간 넘게 남으면 "1:16:23"(7자리), 아니면 "16:23"(5자리)
    private var longForm: Bool { state.start.timeIntervalSinceNow >= 3600 }
    private var key: String { ResultLog.key(state.itemID, state.start) }
    private var extendURL: URL {
        URL(string: "pingapp://extend?id=\(state.itemID)&start=\(Int(state.start.timeIntervalSince1970))")!
    }

    // 잠금화면 카드는 높이가 최대 약 160pt. 위: 사진·제목·남은 시간 / 아래: 말풍선 또는 마무리 체크
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Face(state: state, size: 54)
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(state.title)
                        .font(.system(size: 19.5, weight: .bold))
                        .foregroundStyle(CardStyle.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(state.place.isEmpty ? state.timeLabel : state.timeLabel + " · " + state.place)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(CardStyle.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            bottom
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(CardStyle.background(state))
        .overlay(
            ContainerRelativeShape()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), CardStyle.accent(state).opacity(0.18), Color.white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var trailing: some View {
        if state.result == "done" {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(CardStyle.accent(state))
        } else if started {
            Text("시간 됐어")
                .font(.system(size: 15.5, weight: .bold))
                .foregroundStyle(CardStyle.accent(state))
        } else {
            VStack(alignment: .trailing, spacing: -3) {
                Countdown(state: state)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(CardStyle.accent(state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: longForm ? 146 : 122, alignment: .trailing)
                Text("남음").font(.system(size: 11.5, weight: .medium)).foregroundStyle(CardStyle.sub)
            }
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if state.result == "done" {
            bubble(Text("잘했어! 오늘도 하나 해냈다").font(.system(size: 14.5, weight: .semibold)).foregroundColor(CardStyle.text))
        } else if started {
            HStack(spacing: 12) {
                Text("잘 마무리했어?")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(CardStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(intent: FinishIntent(key: key)) {
                    Text("했어")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CardStyle.base)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(CardStyle.accent(state)))
                }
                .buttonStyle(.plain)
                Link(destination: extendURL) {
                    Text("못 했어")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CardStyle.text)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
        } else if let line = state.line {
            let duo = state.cameoLine != nil
            // 끼어들 때는 메인 말풍선을 끼어든 말풍선 시작 위치에 맞춘다 (14 + 사진 22 + 간격 7)
            VStack(alignment: .leading, spacing: 5) {
                message(name: state.sender, line: line, color: CardStyle.accent(state), small: duo)
                    .padding(.leading, duo ? 43 : 0)
                if let cameo = state.cameoLine {
                    HStack(alignment: .center, spacing: 7) {
                        MiniFace(key: state.cameoAvatarKey, name: state.cameoName ?? "", color: CardStyle.accent(hex: state.cameoHex))
                        message(name: state.cameoName, line: cameo, color: CardStyle.accent(hex: state.cameoHex), small: true)
                    }
                    .padding(.leading, 14)
                }
            }
        }
    }

    /// 이름은 늘 보이고, 문구는 잠금(Face ID 전)·상시표시(AOD)에서 "···"로 가린다
    private func message(name: String?, line: String, color: Color, small: Bool) -> some View {
        let size: CGFloat = small ? 13.5 : 14.5
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let name {
                Text(name).font(.system(size: size, weight: .bold)).foregroundStyle(color)
                    .fixedSize()
            }
            Secret {
                Text(line).font(.system(size: size)).foregroundColor(CardStyle.text)
            }
            .lineLimit(small ? 1 : 2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, small ? 10 : 12)
        .padding(.vertical, small ? 6 : 8)
        .background(RoundedRectangle(cornerRadius: small ? 12 : 14, style: .continuous).fill(CardStyle.bubble))
    }

    private func bubble(_ text: Text) -> some View {
        text
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CardStyle.bubble))
    }
}

/// 잠금 상태(Face ID 전)나 상시표시(AOD)에서는 내용 대신 "···"를 보여준다
struct Secret<Content: View>: View {
    @Environment(\.redactionReasons) private var redaction
    @Environment(\.isLuminanceReduced) private var dimmed
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if redaction.contains(.privacy) || dimmed {
                Text("···")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(CardStyle.sub)
                    .unredacted()
            } else {
                content()
            }
        }
        .privacySensitive()
    }
}

/// 끼어든 사람의 작은 얼굴 (공유 폴더 사진, 없으면 이름 첫 글자)
struct MiniFace: View {
    let key: String?
    let name: String
    let color: Color
    private let size: CGFloat = 22

    var body: some View {
        Group {
            if let key, let url = NextUpAttributes.avatarFile(key), let img = UIImage(contentsOfFile: url.path),
               let small = img.preparingThumbnail(of: CGSize(width: size * 3, height: size * 3)) {
                Image(uiImage: small).resizable().interpolation(.high).scaledToFill()
            } else {
                color.opacity(0.35).overlay {
                    Text(String(name.prefix(1))).font(.system(size: 11, weight: .bold)).foregroundStyle(CardStyle.text)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(color, lineWidth: 1.2))
    }
}
