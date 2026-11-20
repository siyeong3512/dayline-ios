import Foundation

/// 알림 문구(잔소리). 같은 일정·같은 알림 시점이면 늘 같은 문장을 골라서,
/// 목소리 파일도 다시 만들 필요가 없게 한다.
enum Nag {
    static func line(settings: AppSettings, item: ScheduleItem, minutesBefore n: Int) -> String {
        let tone = settings.effectiveTone
        let pool = templates(settings: settings, tone: tone, minutesBefore: n)
        guard !pool.isEmpty else { return "\(ReminderOption.amount(n)) 뒤 시작해요." }
        let seed = "\(item.id)|\(n)|\(tone.rawValue)|\(settings.customTone?.name ?? "")"
        let pick = pool[Int(stableHash(seed) % UInt64(pool.count))]
        return pick
            .replacingOccurrences(of: "{left}", with: ReminderOption.amount(n))
            .replacingOccurrences(of: "{title}", with: item.title)
            .replacingOccurrences(of: "{place}", with: item.place.isEmpty ? "거기" : item.place)
            .replacingOccurrences(of: "{time}", with: item.time)
    }

    /// 보낸 사람 이름이 있는 말투면 그 이름, 아니면 nil
    static func sender(settings: AppSettings) -> String? {
        settings.effectiveTone == .custom ? settings.customTone?.sender : nil
    }

    /// 알림 제목: 보낸 사람이 있으면 그 사람 이름(톡처럼), 없으면 일정 이름
    static func title(settings: AppSettings, item: ScheduleItem) -> String {
        sender(settings: settings) ?? item.title
    }

    /// 알림 본문: 잔소리 + (일정 이름) + 시간·장소
    static func body(settings: AppSettings, item: ScheduleItem, minutesBefore n: Int) -> String {
        let info = item.place.isEmpty ? item.time : "\(item.time) · \(item.place)"
        if settings.effectiveTone == .plain { return "\(ReminderOption.label(n)) · \(info)" }
        let text = line(settings: settings, item: item, minutesBefore: n)
        if sender(settings: settings) != nil { return text + "\n" + item.title + " · " + info }
        return text + "\n" + info
    }

    /// 목소리로 읽을 문장 (ㅋㅋ·ㅏ·이모지처럼 TTS가 이상하게 읽는 글자는 뺀다)
    static func spoken(settings: AppSettings, item: ScheduleItem, minutesBefore n: Int) -> String {
        if settings.effectiveTone == .plain { return "\(item.title), \(ReminderOption.amount(n)) 뒤에 시작해요." }
        let text = line(settings: settings, item: item, minutesBefore: n)
        if settings.effectiveTone == .custom { return speakable(text) }
        return "\(item.title). " + text
    }

    static func speakable(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            let v = scalar.value
            let isJamo = (0x3131...0x318E).contains(v)           // ㅋ ㅎ ㅏ ㅠ 같은 낱자
            let isEmoji = scalar.properties.isEmojiPresentation || (0x1F000...0x1FAFF).contains(v)
                || (0x2600...0x27BF).contains(v) || v == 0xFE0F || v == 0x200D
            if isJamo || isEmoji { continue }
            out.unicodeScalars.append(scalar == "~" ? " " : scalar)
        }
        var collapsed = out.replacingOccurrences(of: #"([!?.])\1+"#, with: "$1", options: .regularExpression)
        collapsed = collapsed.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stage(_ n: Int) -> Int { n <= 10 ? 2 : n <= 60 ? 1 : 0 }

    private static func templates(settings: AppSettings, tone: NagTone, minutesBefore n: Int) -> [String] {
        let stage = stage(n)
        switch tone {
        case .plain:
            return ["{left} 뒤 시작해요."]
        case .custom:
            return settings.customTone?.pool(stage: stage) ?? []
        case .gentle:
            return [
                ["{title}까지 {left} 남았어요. 천천히 준비해요.",
                 "오늘 {title} 있는 날이에요. 미리 챙겨두면 마음이 편해요."],
                ["{left} 뒤 {title}. 슬슬 준비해볼까요?",
                 "{place}로 갈 시간이 다가와요. 물 한 잔 챙겨요."],
                ["{left} 남았어요. 이제 출발해요!",
                 "곧 {title} 시작이에요. 오늘도 잘할 거예요."]
            ][stage]
        case .friend:
            return [
                ["야, {title} {left} 남았다. 미리 챙겨둬.",
                 "{title} 있는 거 안 잊었지? {left} 남음."],
                ["{left} 뒤 {title}. 가방 챙겼냐.",
                 "지금 나가야 여유 있다. {place} 가자."],
                ["{left} 남았다. 아직 침대면 일어나라.",
                 "{title} 곧 시작. 뛰어."]
            ][stage]
        case .strict:
            return [
                ["{title} {left} 전. 오늘은 핑계 없다.",
                 "{left} 뒤 {title}. 준비 안 했으면 지금 해."],
                ["{left} 남았다. 폰 내려놓고 준비해.",
                 "{title} {left} 전. 늦으면 네 손해다."],
                ["{left}. 지금 안 나가면 늦는다.",
                 "{title} 곧 시작. 늦지 마라."]
            ][stage]
        }
    }

    /// 실행할 때마다 바뀌지 않는 해시(djb2)
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &<< 5) &+ h &+ UInt64(b) }
        return h
    }
}
