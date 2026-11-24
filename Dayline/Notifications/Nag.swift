import Foundation

/// 알림 문구(잔소리). 같은 일정·같은 알림 시점이면 늘 같은 문장을 골라서,
/// 목소리 파일도 다시 만들 필요가 없게 한다.
enum Nag {
    static func line(settings: AppSettings, item: ScheduleItem, minutesBefore n: Int, salt: String = "", card: Bool = false) -> String {
        let tone = settings.effectiveTone
        var pool = templates(settings: settings, tone: tone, minutesBefore: n)
        if card, tone == .custom, let c = settings.currentCustom?.cardPool(stage: stage(n)), !c.isEmpty { pool = c }
        guard !pool.isEmpty else { return "\(ReminderOption.amount(n)) 뒤 시작해요." }
        let seed = "\(item.id)|\(n)|\(tone.rawValue)|\(settings.currentCustom?.name ?? "")" + salt
        let pick = pool[Int(stableHash(seed) % UInt64(pool.count))]
        return pick
            .replacingOccurrences(of: "{left}", with: ReminderOption.amount(n))
            .replacingOccurrences(of: "{title}", with: item.title)
            .replacingOccurrences(of: "{place}", with: item.place.isEmpty ? "거기" : item.place)
            .replacingOccurrences(of: "{time}", with: item.time)
            .josaFixed
    }

    /// 잠금화면 카드 문구: 말투 파일에 카드 전용 문장(cardEarly/cardSoon/cardUrgent)이 있으면 그걸 쓰고,
    /// 없으면 알림 문장을 쓴다. 카드는 늘 한 줄(나눠 보낸 조각은 이어 붙인다).
    static func cardLine(settings: AppSettings, item: ScheduleItem, minutesBefore n: Int, salt: String = "") -> String {
        pieces(line(settings: settings, item: item, minutesBefore: n, salt: salt, card: true)).joined(separator: " ")
    }

    /// 설정 > 보낸 사람에서 고른 사람 이름 (없으면 nil → 알림 제목은 일정 이름)
    static func sender(settings: AppSettings) -> String? {
        settings.activePerson?.name
    }

    // MARK: 할 일 체크

    /// 할 일 체크 알림 문장. period: "오늘"/"이번 주"/"이번 달"
    static func todoLine(settings: AppSettings, period: String, count: Int, seed: String) -> String {
        let pool: [String]
        switch settings.effectiveTone {
        case .custom:
            let lines = settings.currentCustom?.todo ?? []
            pool = lines.isEmpty ? friendTodo : lines
        case .plain: pool = ["{period} 할 일 {count}개가 남았어요."]
        case .gentle: pool = ["{period} 할 일 {count}개 남았어요. 하나씩 해볼까요?",
                              "{period} 거의 다 왔어요. {count}개만 더 하면 끝이에요."]
        case .friend: pool = friendTodo
        case .strict: pool = ["{period} 할 일 {count}개 미완료. 핑계 없이 지금 해.",
                              "{count}개 남았다. 폰 내려놓고 끝내라."]
        }
        let pick = pool[Int(stableHash(seed + settings.effectiveTone.rawValue) % UInt64(pool.count))]
        return pick
            .replacingOccurrences(of: "{period}", with: period)
            .replacingOccurrences(of: "{count}", with: "\(count)")
            .josaFixed
    }

    private static let friendTodo = ["야 {period} 할 일 {count}개 남았다. 자기 전에 끝내자.",
                                     "{period} 거 다 했냐? 아직 {count}개 남음."]

    /// 말투 문장 안의 줄바꿈(\n)은 '여러 번 나눠 보내기'. 최대 4조각(넘치면 마지막에 붙인다)
    static func pieces(_ s: String) -> [String] {
        var p = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if p.count > 4 { p = Array(p.prefix(3)) + [p.dropFirst(3).joined(separator: " ")] }
        return p.isEmpty ? [s] : p
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
        let text = pieces(line(settings: settings, item: item, minutesBefore: n)).joined(separator: " ")
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
            return settings.currentCustom?.pool(stage: stage) ?? []
        case .gentle:
            return [
                ["{title}까지 {left} 남았어요. 천천히 준비해요.",
                 "오늘 {title} 있는 날이에요. 미리 챙겨두면 마음이 편해요."],
                ["{left} 뒤 {title}. 슬슬 준비해볼까요?",
                 "{place}(으)로 갈 시간이 다가와요. 물 한 잔 챙겨요."],
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

// MARK: - 조사 고르기

/// 문장 속 "을/를", "이/가", "(으)로", "(이)" 같은 표기를 바로 앞 글자의 받침에 맞게 하나로 고른다.
/// 예) "{title}을/를 챙겨" → "자료구조를 챙겨", "{place}(으)로 가자" → "K501로 가자"
enum Josa {
    /// (표기, 받침 있을 때, 받침 없을 때). 긴 표기를 먼저 찾는다.
    private static let rules: [(String, String, String)] = [
        ("이에요/예요", "이에요", "예요"), ("이라서/라서", "이라서", "라서"),
        ("이랑/랑", "이랑", "랑"), ("이야/야", "이야", "야"), ("이나/나", "이나", "나"),
        ("이라/라", "이라", "라"), ("이지/지", "이지", "지"),
        ("이/가", "이", "가"), ("가/이", "이", "가"),
        ("을/를", "을", "를"), ("를/을", "을", "를"),
        ("은/는", "은", "는"), ("는/은", "은", "는"),
        ("과/와", "과", "와"), ("와/과", "과", "와"),
        ("아/야", "아", "야"), ("(이)", "이", "")
    ]

    static func fix(_ text: String) -> String {
        var s = text
        for token in ["(으)로", "으로/로"] {
            s = replace(s, token) { b in b == .consonant ? "으로" : "로" }
        }
        for (token, yes, no) in rules {
            s = replace(s, token) { b in b == .vowel ? no : yes }
        }
        return s
    }

    enum Final { case vowel, consonant, rieul }

    private static func replace(_ s: String, _ token: String, pick: (Final?) -> String) -> String {
        var out = s
        var searchEnd = out.endIndex
        while let r = out.range(of: token, options: .backwards, range: out.startIndex..<searchEnd) {
            out.replaceSubrange(r, with: pick(final(before: r.lowerBound, in: out)))
            searchEnd = r.lowerBound
        }
        return out
    }

    /// 바로 앞 글자의 받침. 따옴표·괄호는 건너뛰고, 공백이나 문장 처음을 만나면 알 수 없음(nil).
    private static func final(before i: String.Index, in s: String) -> Final? {
        var j = i
        while j > s.startIndex {
            j = s.index(before: j)
            let c = s[j]
            if c.isWhitespace { return nil }
            if "'\"‘’“”)]」』".contains(c) { continue }
            return final(of: c)
        }
        return nil
    }

    private static func final(of c: Character) -> Final? {
        guard let v = c.unicodeScalars.first?.value else { return nil }
        if (0xAC00...0xD7A3).contains(v) {
            let jong = (v - 0xAC00) % 28
            return jong == 0 ? .vowel : jong == 8 ? .rieul : .consonant
        }
        switch c {
        case "0", "3", "6": return .consonant       // 영 삼 육
        case "1", "7", "8": return .rieul      // 일 칠 팔
        case "2", "4", "5", "9": return .vowel
        default: break
        }
        switch c.lowercased() {
        case "l": return .rieul
        case "m", "n": return .consonant
        case _ where c.isLetter && c.isASCII: return .vowel
        default: return nil
        }
    }
}

extension String {
    var josaFixed: String { Josa.fix(self) }
}
