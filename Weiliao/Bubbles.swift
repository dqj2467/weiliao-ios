import SwiftUI
import AVFoundation
import Photos
import PhotosUI

// MARK: - 消息气泡

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
            DispatchQueue.main.async {
                guard ok else { PayDialogs.toast("请在系统设置里允许微聊使用麦克风"); return }
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
                guard self.rec != nil else { PayDialogs.toast("录音启动失败"); return }
                self.rec?.record()
                self.started = Date()
                self.recording = true
            }
        }
    }

    func finish(_ done: @escaping (String, Int) -> Void) {
        guard recording, let r = rec else {
            recording = false
            if rec == nil { DispatchQueue.main.async { PayDialogs.toast("录音不可用") } }
            return
        }
        r.stop()
        recording = false
        let durMs = Int(Date().timeIntervalSince(started) * 1000)
        guard durMs >= 600 else { DispatchQueue.main.async { PayDialogs.toast("说话时间太短") }; return }
        let dur = max(1, durMs / 1000)
        let data = try? Data(contentsOf: r.url)
        guard let data = data, !data.isEmpty else {
            DispatchQueue.main.async { PayDialogs.toast("录音失败") }
            return
        }
        Api.shared.upload("/Home/Index/voiceUpload.html", fileData: data, fileName: "voice.m4a") { up in
            let path = up?.str("voice_path") ?? ""
            DispatchQueue.main.async {
                if path.isEmpty { PayDialogs.toast("语音上传失败") } else { done(path, dur) }
            }
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
