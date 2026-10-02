import SwiftUI
import AVFoundation
import CoreImage

// ============================================================
// 扫一扫加好友（v1.31 2026-10-03，与安卓 v5.73 QrActivity/ScanActivity 同构）
//   MyQrSheet  ：我页资料行 → 我的二维码（内容 weiliao://add?u=<账号>，账号=fy_user.phone，搜索只认账号）
//   ScanQrSheet：我页「扫一扫」→ 相机识别（AVFoundation 原生 QR，无第三方依赖）
//                命中本端专属码或纯账号文本 → 进 AddFriendSheet 自动搜索
// ============================================================

/// zxing/CIQRCodeGenerator 生成二维码（黑码白底）
func wlMakeQrImage(_ content: String, size: CGFloat = 240) -> UIImage? {
    guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    f.setValue(Data(content.utf8), forKey: "inputMessage")
    f.setValue("M", forKey: "inputCorrectionLevel")
    guard let out = f.outputImage else { return nil }
    let scale = max(1, ceil(size / max(out.extent.width, 1)))
    let scaled = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}

/// 扫码结果 → 账号（未命中返回 nil）
func wlParseQrAccount(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "weiliao://add?u="
    if t.hasPrefix(prefix) {
        let u = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return u.range(of: "^[A-Za-z0-9_]{1,32}$", options: .regularExpression) != nil ? u : nil
    }
    // 纯账号文本：11 位手机号 或 字母开头字母数字账号（4-20 位）
    if t.range(of: "^1\\d{10}$", options: .regularExpression) != nil { return t }
    if t.range(of: "^[A-Za-z][A-Za-z0-9_]{3,19}$", options: .regularExpression) != nil { return t }
    return nil
}

// MARK: - 我的二维码

struct MyQrSheet: View {
    @Environment(\.presentationMode) var mode
    var phone: String
    var nickname: String
    @State var qr: UIImage? = nil

    var body: some View {
        VStack(spacing: 0) {
            sheetHead("我的二维码")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(nickname.isEmpty ? "我" : nickname)
                        .font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                        .padding(.top, 30)
                    if phone.isEmpty {
                        Text("当前账号未设置账号信息，暂无法生成二维码")
                            .font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151))
                            .frame(width: 240, height: 240)
                    } else {
                        Group {
                            if let qr = qr {
                                Image(uiImage: qr).resizable().interpolation(.none).scaledToFit()
                            } else {
                                Text("二维码生成失败")
                                    .font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                            }
                        }
                        .frame(width: 240, height: 240)
                        .padding(.top, 22)
                    }
                    Text("扫一扫上面的二维码图，向我添加好友")
                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x888888))
                        .padding(.top, 22)
                    Text("把二维码出示给对方，对方扫一扫即可添加你")
                        .font(.system(size: 12)).foregroundColor(Color(hex: 0xAAAAAA))
                        .padding(.top, 20).padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(hex: 0xF5F6F7))
        .onAppear {
            if !phone.isEmpty { qr = wlMakeQrImage("weiliao://add?u=" + phone, size: 720) }
        }
    }

    private func sheetHead(_ title: String) -> some View {
        ZStack(alignment: .leading) {
            ZStack {
                Color(hex: 0xEDEDED)
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(hex: 0x262626))
            }
            .frame(height: 48)
            Button(action: { mode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: 0x333333)).padding(.leading, 14)
            }
        }
    }
}

// MARK: - 扫一扫（相机）

/// 原生扫码控制器：AVCaptureSession + MetadataOutput（.qr）
final class QrScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            DispatchQueue.main.async { self?.setup(ok: ok) }
        }
    }

    private func setup(ok: Bool) {
        guard ok else {
            let lb = UILabel()
            lb.text = "未授权相机，无法扫一扫\n请到 系统设置 → 微聊 打开相机权限"
            lb.numberOfLines = 0
            lb.textAlignment = .center
            lb.textColor = .white
            lb.font = .systemFont(ofSize: 14)
            lb.frame = view.bounds.insetBy(dx: 30, dy: 0)
            lb.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(lb)
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        if session.canAddOutput(out) {
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()
        preview.session = session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        preview.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr, let s = obj.stringValue else { return }
        session.stopRunning()
        onFound?(s)
    }
}

struct ScanQrCamera: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> QrScannerVC {
        let vc = QrScannerVC()
        vc.onFound = onFound
        return vc
    }
    func updateUIViewController(_ vc: QrScannerVC, context: Context) {}
}

/// 扫一扫全屏页：相机 + 取景框 + 提示；识别成功回调账号
struct ScanQrSheet: View {
    @Environment(\.presentationMode) var mode
    var onFound: (String) -> Void
    @State var foundText: String? = nil

    var body: some View {
        ZStack {
            ScanQrCamera { s in
                guard foundText == nil else { return }
                foundText = s
                let acc = wlParseQrAccount(s)
                mode.wrappedValue.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onFound(acc ?? "")
                }
            }
            // 取景蒙层：中央方框（even-odd 挖洞）
            GeometryReader { g in
                let side = min(g.size.width, g.size.height) * 0.62
                let rect = CGRect(x: (g.size.width - side) / 2,
                                  y: (g.size.height - side) / 2 - 20,
                                  width: side, height: side)
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: g.size))
                    p.addRect(rect)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x07C160), lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.4).frame(height: 48)
                    Text("扫一扫").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                    Button(action: { mode.wrappedValue.dismiss() }) {
                        Text("‹ 返回").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                            .padding(.leading, 14)
                    }
                }
                Spacer()
                Text("对准对方的二维码，即可添加好友")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
                    .padding(.bottom, 70)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
    }
}

/// 扫码结果包装（sheet(item:) 用）
struct ScanResult: Identifiable {
    let id = UUID()
    var kw: String   // 命中的账号；空串=未命中
}
