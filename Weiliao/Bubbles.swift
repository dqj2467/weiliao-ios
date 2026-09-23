import SwiftUI
import AVFoundation
import Photos
import PhotosUI

// MARK: - 消息气泡

struct Bubble: View {
    var m: Msg
    var onTapImage: () -> Void
    var onTapHb: () -> Void
    var onTapZz: () -> Void
    var onRecall: () -> Void

    var body: some View {
        Group {
            if m.msgtype == "rc" {
                Text(m.mine ? "你撤回了一条消息" : "\(m.nickname) 撤回了一条消息")
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if m.mine { Spacer(minLength: 48) }
                    Avatar(url: m.avatar, fallback: m.nickname, size: 40).padding(.top, 14)
                    VStack(alignment: m.mine ? .trailing : .leading, spacing: 3) {
                        if !m.mine {
                            Text(m.nickname).font(.system(size: 12)).foregroundColor(.gray)
                        }
                        bubbleCore
                        Text(chatTime(m.time)).font(.system(size: 10)).foregroundColor(.gray)
                    }
                    if !m.mine { Spacer(minLength: 48) }
                }
            }
        }
    }

    @ViewBuilder private var bubbleCore: some View {
        if m.msgtype == "hb" {
            Button(action: onTapHb) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.text).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(m.hbDone == 1 ? "红包已领取完" : (m.hbMine == 1 ? "你已领取" : "点开领取红包"))
                        .font(.system(size: 12)).foregroundColor(Color(hex: 0xFFF3E0))
                }
                .padding(12).background(Color(hex: 0xFA9D3B)).cornerRadius(8)
            }
        } else if m.msgtype == "zz" {
            Button(action: onTapZz) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.zzAmount.isEmpty ? "转账" : m.zzAmount)
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    Text(m.text).font(.system(size: 12)).foregroundColor(Color(hex: 0xFFF3E0))
                }
                .padding(12).background(Color(hex: 0xFA9D3B)).cornerRadius(8)
            }
        } else if m.type == 2 {
            RemoteImage(url: m.text)
                .frame(width: 140, height: 160)
                .cornerRadius(8)
                .onTapGesture(perform: onTapImage)
        } else if m.type == 3 {
            Button(action: { playVoice() }) {
                Text("▶ 语音 \(durText())\"")
                    .foregroundColor(.black)
                    .padding(10).background(m.mine ? Color(hex: 0xA5E75A) : Color.white)
                    .cornerRadius(8)
            }
        } else {
            Text(m.text)
                .padding(10).background(m.mine ? Color(hex: 0xA5E75A) : Color.white)
                .cornerRadius(8)
                .contextMenu {
                    if m.mine { Button("撤回", action: onRecall) }
                }
        }
    }

    @State var player: AVAudioPlayer?

    private func durText() -> Int {
        if let r = m.text.range(of: "|dur=") {
            return Int(m.text[r.upperBound...]) ?? 1
        }
        return 1
    }

    private func playVoice() {
        let path = m.text.components(separatedBy: "|dur=").first ?? m.text
        guard let url = URL(string: Api.host + path) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func chatTime(_ ts: Int64) -> String {
        guard ts > 0 else { return "" }
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        let now = Calendar.current
        if now.isDateInToday(d) {
            fmt.dateFormat = "HH:mm"
        } else if now.isDateInYesterday(d) {
            fmt.dateFormat = "'昨天' HH:mm"
        } else {
            fmt.dateFormat = "M月d日 HH:mm"
        }
        return fmt.string(from: d)
    }
}

struct RemoteImage: View {
    var url: String
    @State var img: UIImage?
    var body: some View {
        Group {
            if let img = img { Image(uiImage: img).resizable().scaledToFit() }
            else { Color(.systemGray5) }
        }
        .onAppear {
            Api.shared.fetchImage(url) { d in
                if let d = d, let i = UIImage(data: d) {
                    DispatchQueue.main.async { img = i }
                }
            }
        }
    }
}

// MARK: - 录音

final class Recorder {
    var recording = false
    private var rec: AVAudioRecorder?
    private var started = Date()

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord)
        try? session.setActive(true)
        session.requestRecordPermission { ok in
            guard ok else { return }
            DispatchQueue.main.async {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("v_\(Int(Date().timeIntervalSince1970)).m4a")
                let s = AVAudioSession.sharedInstance()
                try? s.setCategory(.playAndRecord, mode: .default)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
                self.rec = try? AVAudioRecorder(url: url, settings: settings)
                self.rec?.record()
                self.started = Date()
                self.recording = true
            }
        }
    }

    func finish(_ done: @escaping (String, Int) -> Void) {
        guard recording, let r = rec else { return }
        r.stop()
        recording = false
        let dur = Int(Date().timeIntervalSince(started))
        guard dur >= 1 else { return }
        let data = try? Data(contentsOf: r.url)
        guard let data = data, !data.isEmpty else { return }
        Api.shared.upload("/Home/Index/voiceUpload.html", fileData: data, fileName: "voice.m4a") { up in
            let path = up?.str("voice_path") ?? ""
            if !path.isEmpty { done(path, dur) }
        }
    }
}

// MARK: - 图片选择（PHPicker iOS14 可用）

struct ImagePicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void
    @Environment(\.presentationMode) var mode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.mode.wrappedValue.dismiss()
            guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else {
                parent.onPick(nil)
                return
            }
            item.loadObject(ofClass: UIImage.self) { img, _ in
                DispatchQueue.main.async { self.parent.onPick(img as? UIImage) }
            }
        }
    }
}
