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
