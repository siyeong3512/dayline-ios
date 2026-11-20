import AVFoundation
import Foundation

/// 잔소리 문장을 TTS로 음성 파일(.caf)로 만들어 Library/Sounds에 저장한다.
/// iOS는 이 폴더의 소리를 알림음으로 쓸 수 있어서, 앱이 닫혀 있어도 알림이 울릴 때 목소리가 재생된다.
/// (알림음은 30초 미만이어야 한다. 잔소리는 몇 초짜리라 문제없다.)
final class VoiceMaker {
    private var synth: AVSpeechSynthesizer?

    static var soundsDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// 한국어 목소리 + (허용한 경우) 개인 음성
    static func voices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ko") || $0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    static func voice(for id: String?) -> AVSpeechSynthesisVoice? {
        if let id, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return AVSpeechSynthesisVoice(language: "ko-KR")
    }

    static func fileName(text: String, voiceID: String?) -> String {
        "dl-\(Nag.stableHash(text + "|" + (voiceID ?? "default"))).caf"
    }

    /// 이미 만든 파일이 있으면 재사용. 실패하면 nil(기본 알림음 사용)
    func soundFile(text: String, voiceID: String?) async -> String? {
        let dir = Self.soundsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = Self.fileName(text: text, voiceID: voiceID)
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        let ok = await synthesize(text: text, voiceID: voiceID, to: url)
        if !ok { try? FileManager.default.removeItem(at: url) }
        return ok ? name : nil
    }

    /// 지금 쓰는 파일 말고는 정리
    func cleanup(keeping names: Set<String>) {
        let dir = Self.soundsDir
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix("dl-") && !names.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    private func synthesize(text: String, voiceID: String?, to url: URL) async -> Bool {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: voiceID)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        let synth = AVSpeechSynthesizer()
        self.synth = synth
        let state = WriteState()

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // 일부 iOS 버전은 마지막 빈 버퍼를 안 보내므로 시간 제한을 둔다
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                state.finish { cont.resume(returning: $0) }
            }
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    state.finish { cont.resume(returning: $0) }
                    return
                }
                state.append(pcm, to: url)
            }
        }
    }
}

/// 합성 콜백(다른 스레드)에서 파일 쓰기와 '한 번만 끝내기'를 안전하게 처리
private final class WriteState {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var wroteFrames = false
    private var failed = false
    private var done = false

    func append(_ pcm: AVAudioPCMBuffer, to url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !done, !failed else { return }
        do {
            if file == nil {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: pcm.format.sampleRate,
                    AVNumberOfChannelsKey: Int(pcm.format.channelCount),
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: pcm.format.commonFormat,
                                       interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            wroteFrames = true
        } catch {
            failed = true
        }
    }

    func finish(_ resume: (Bool) -> Void) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let ok = wroteFrames && !failed
        file = nil // 파일 닫기
        lock.unlock()
        resume(ok)
    }
}
