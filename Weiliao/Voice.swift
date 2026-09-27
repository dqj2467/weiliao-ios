import AVFoundation

/// 充值/提现语音播报（v1.17，安卓 VoiceService 同口径）：
/// 每 10 秒轮询 /Api/voice/pull.html（与登录会话同 cookie），拉到会员的充值/提现申请
/// 用 AVSpeechSynthesizer 中文念出。播报文案与安卓 v5.15 完全一致：
///   充值（金额>0）：收到充值申请 20.5 元 / 未填金额：您有新的充值申请，请及时处理
///   提现：收到提现申请 20 元
/// 开关：「我」页「语音播报」行，存 UserDefaults("voice_on")，默认开。
/// 说明：iOS 无常驻前台服务，退后台后依托「后台音频」模式尽力播报（有音频在播期间不会被挂起），
///       长时间锁屏可能被系统挂起，这点与安卓常驻通知栏方案有差异。
final class VoiceBroadcaster {
    static let shared = VoiceBroadcaster()

    private var timer: Timer?
    private var polling = false
    private let synth = AVSpeechSynthesizer()

    private init() {
        // playback 会话绕过静音键；配合 Info.plist UIBackgroundModes=audio 尽力后台播
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "voice_on") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voice_on") }
    }

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard enabled, !polling else { return }
        polling = true
        Api.shared.post("/Api/voice/pull.html",
                        form: ["t": String(Int64(Date().timeIntervalSince1970 * 1000))]) { [weak self] r in
            guard let self = self else { return }
            var events: [String] = []
            if let r = r, r.status == 200 {
                for ev in r.arr {          // data 是数组：[{type, amount}]
                    let type = ev.int("type")
                    let amount = Self.trimAmount(ev.str("amount"))
                    if type == 2 {
                        events.append("收到提现申请 " + amount + " 元")
                    } else if amount.isEmpty || amount == "0" {
                        events.append("您有新的充值申请，请及时处理")
                    } else {
                        events.append("收到充值申请 " + amount + " 元")
                    }
                }
            }
            DispatchQueue.main.async {
                self.polling = false
                for t in events { self.speak(t) }
                // 有积压时快速补拉（安卓同款：连发不干等 10 秒）
                if !events.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.poll() }
                }
            }
        }
    }

    /// 金额去尾零（安卓 BigDecimal.stripTrailingZeros 同效果）
    private static func trimAmount(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "" }
        if let d = Double(t) {
            let v = (d * 100).rounded() / 100
            if v == v.rounded() { return String(Int64(v)) }
            t = String(format: "%.2f", v)
        }
        while t.hasSuffix("0") && t.contains(".") { t = String(t.dropLast()) }
        if t.hasSuffix(".") { t = String(t.dropLast()) }
        return t
    }

    /// TTS 播报（打断上一条，插队播放）
    private func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.speak(u)
    }
}
