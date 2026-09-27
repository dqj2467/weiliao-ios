import SwiftUI
import UIKit
import PhotosUI

// MARK: - 通用工具

func fmt2(_ n: Double) -> String {
    String(format: "%.2f", (n * 100).rounded() / 100)
}

/// 原生弹窗工具（iOS14 兼容）
final class PayDialogs {

    private static func topVC() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        // v1.15：沿 presented 链走到底（root 被 fullScreenCover 占用时直接 present 会静默失败 → toast/confirm 全部无反应）
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }

    static func alert(_ title: String, _ message: String) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好的", style: .default))
        vc.present(a, animated: true)
    }

    /// 二次确认弹窗（确定/取消）
    static func confirm(_ message: String, ok: @escaping () -> Void) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "确定", style: .destructive) { _ in ok() })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        vc.present(a, animated: true)
    }

    static func toast(_ message: String) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { a.dismiss(animated: true) }
        vc.present(a, animated: true)
    }

    static func pickImage(_ cb: @escaping (UIImage?) -> Void) {
        guard let vc = topVC() else { return }
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg)
        let holder = PickerHolder(cb: cb)
        p.delegate = holder
        objc_setAssociatedObject(vc, "picker_holder", holder, .OBJC_ASSOCIATION_RETAIN)
        vc.present(p, animated: true)
    }
}

final class PickerHolder: NSObject, PHPickerViewControllerDelegate {
    let cb: (UIImage?) -> Void
    init(cb: @escaping (UIImage?) -> Void) { self.cb = cb }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else {
            cb(nil)
            return
        }
        item.loadObject(ofClass: UIImage.self) { img, _ in
            DispatchQueue.main.async { self.cb(img as? UIImage) }
        }
    }
}

// MARK: - 带支付密码闸门的提交（安卓 ChatActivity.postWithPayPwd 同款）
// 第一次不带 paypwd；后端 need_pwd=1 且 pwd_set=0 → 弹设置；已设置 → 弹六格输入后重发。
// 成功静默、失败才提示（v5.47 口径）。

final class PayPwdGate {
    static func post(_ path: String, params: [String: String], done: @escaping (JSONObject?) -> Void) {
        Api.shared.post(path, form: params) { r in
            if let r = r, r.status == 0, r.int("need_pwd") == 1 {
                DispatchQueue.main.async {
                    if r.int("pwd_set") == 0 {
                        PayDialogs.toast(r.str("info").isEmpty ? "请先设置支付密码" : r.str("info"))
                        PayPwdSheet.shared.showSet = true
                    } else {
                        PayPwdSheet.shared.onPwd = { pwd in
                            var p2 = params; p2["paypwd"] = pwd
                            PayPwdGate.post(path, params: p2, done: done)
                        }
                        PayPwdSheet.shared.showAsk = true
                    }
                }
                return
            }
            if r == nil {
                DispatchQueue.main.async { PayDialogs.toast("网络异常") }
            } else if let r = r, r.status != 1 {
                let info = r.str("info").isEmpty ? r.msg : r.str("info")
                DispatchQueue.main.async { PayDialogs.toast(info.isEmpty ? "操作失败" : info) }
            }
            done(r)
        }
    }
}

// MARK: - 支付密码弹层全局开关

final class PayPwdSheet: ObservableObject {
    static let shared = PayPwdSheet()
    @Published var showSet = false
    @Published var showAsk = false
    var onPwd: ((String) -> Void)?
}

// MARK: - 六格数字输入（安卓 v5.35/37 同款：单隐藏输入框驱动 6 格，宽度按弹窗自适应）

struct PayPwdCells: View {
    @Binding var text: String
    var cellH: CGFloat = 52
    @State var focused = true

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let cw = (w - 5 * 8) / 6
            ZStack {
                // 隐藏输入框（透明文字），覆盖整个区域
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .foregroundColor(.clear)
                    .accentColor(.clear)
                    .onChange(of: text) { v in
                        let filtered = String(v.filter { $0.isNumber }.prefix(6))
                        if filtered != text { text = filtered }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<6, id: \.self) { i in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(text.count > i ? Color(hex: 0x7F7F7F) : Color(hex: 0xDCDCDC), lineWidth: 1))
                            if i < text.count {
                                Text("•").font(.system(size: cellH * 0.5, weight: .bold)).foregroundColor(Color(hex: 0x111111))
                            }
                        }.frame(width: cw, height: cellH)
                    }
                }
            }
        }
        .frame(height: cellH)
    }
}

// MARK: - 输入支付密码弹窗（居中卡片，暗底）

struct PayPwdAskView: View {
    @Environment(\.presentationMode) var mode
    @State var pwd = ""
    @State var err = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(spacing: 0) {
                Text("请输入支付密码").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x111111))
                Text(err.isEmpty ? " " : err).font(.system(size: 12)).foregroundColor(Color(hex: 0xFA5151)).padding(.top, 8)
                PayPwdCells(text: $pwd).padding(.top, 12)
                Button(action: confirm) {
                    Text("确 定").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color(hex: 0x07C160)).cornerRadius(8)
                }.padding(.top, 18)
            }
            .padding(20)
            .background(Color.white.cornerRadius(14))
            .padding(.horizontal, 30)
            .onChange(of: pwd) { v in
                if v.count == 6 { confirm() }
            }
        }
    }

    private func confirm() {
        guard pwd.count == 6 else { err = "请输入 6 位支付密码"; return }
        mode.wrappedValue.dismiss()
        let cb = PayPwdSheet.shared.onPwd
        PayPwdSheet.shared.onPwd = nil
        cb?(pwd)
    }
}

// MARK: - 设置支付密码弹窗

struct PayPwdSetView: View {
    @Environment(\.presentationMode) var mode
    @State var old = ""
    @State var p1 = ""
    @State var p2 = ""
    @State var msg = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    Text("设置支付密码").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x111111))
                    Text("6 位数字，用于发红包 / 转账确认").font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                    secure("原支付密码（首次设置不用填）", $old)
                    secure("新的 6 位支付密码", $p1)
                    secure("再输一遍确认", $p2)
                    if !msg.isEmpty {
                        Text(msg).font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151))
                    }
                    Button(action: save) {
                        Text("保 存").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color(hex: 0x07C160)).cornerRadius(8)
                    }.padding(.top, 6)
                }
                .padding(20)
                .background(Color.white.cornerRadius(14))
            }
            .padding(.horizontal, 30)
        }
    }

    private func secure(_ ph: String, _ b: Binding<String>) -> some View {
        SecureField(ph, text: b)
            .keyboardType(.numberPad)
            .font(.system(size: 15))
            .frame(height: 42).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
    }

    private func save() {
        guard p1.count == 6 else { msg = "支付密码必须是 6 位数字"; return }
        guard p1 == p2 else { msg = "两次输入不一致"; return }
        Api.shared.post("/Home/Paypwd/save.html",
                        form: ["oldpwd": old, "pwd": p1, "pwd2": p2]) { r in
            DispatchQueue.main.async {
                if r?.status == 1 {
                    mode.wrappedValue.dismiss()
                    PayDialogs.toast("设置成功")
                } else {
                    msg = r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常"
                }
            }
        }
    }
}

// MARK: - 微信式「确认转账」横向长方形弹层（安卓 v5.41 zzConfirm 1:1）

struct ZZConfirmView: View {
    var face: String
    var name: String
    var amount: Double
    var fee: Double
    var onOk: () -> Void
    @Environment(\.presentationMode) var mode

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if !face.isEmpty {
                            Avatar(url: face, fallback: name, size: 32)
                        }
                        Text("转账给 " + name).font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                    }
                    Text("¥" + fmt2(amount)).font(.system(size: 30, weight: .bold)).foregroundColor(Color(hex: 0x262626)).padding(.top, 12)
                    if fee > 0 {
                        let feeLine = "平台服务费 ¥" + fmt2(fee) + "，对方实收 ¥" + fmt2(amount - fee)
                        Text(feeLine)
                            .font(.system(size: 13)).foregroundColor(Color(hex: 0xE6A23C)).padding(.top, 6)
                    }
                    Text("请再次确认收款方与金额").font(.system(size: 13)).foregroundColor(Color(hex: 0x999999)).padding(.top, 6)
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)

                Rectangle().fill(Color(hex: 0xE5E5E5)).frame(height: 1)
                HStack(spacing: 0) {
                    Button(action: { mode.wrappedValue.dismiss() }) {
                        Text("取消").font(.system(size: 16)).foregroundColor(Color(hex: 0x666666))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                    Rectangle().fill(Color(hex: 0xE5E5E5)).frame(width: 1)
                    Button(action: { mode.wrappedValue.dismiss(); onOk() }) {
                        Text("转账").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x1AAD19))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }
                }
            }
            .background(Color.white.cornerRadius(10))
            .padding(.horizontal, 30)
        }
    }
}

// MARK: - 底部菜单（安卓 showSheetMenu 同款：标题 + 选项列表）

struct SheetMenuView: View {
    var title: String
    var items: [String]
    var onPick: (Int) -> Void
    @Environment(\.presentationMode) var mode

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(spacing: 0) {
                if !title.isEmpty {
                    Text(title).font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                        .frame(maxWidth: .infinity).frame(height: 40)
                    Rectangle().fill(Color(hex: 0xEEEEEE)).frame(height: 0.5)
                }
                ForEach(items.indices, id: \.self) { i in
                    Button(action: { mode.wrappedValue.dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPick(i) }
                    }) {
                        Text(items[i]).font(.system(size: 16)).foregroundColor(Color(hex: 0x262626))
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 0.5)
                }
                Button(action: { mode.wrappedValue.dismiss() }) {
                    Text("取消").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x666666))
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
            }
            .background(Color(hex: 0xF7F7F7))
        }
    }
}

// MARK: - 底部弹层容器（群金额明细/分润统计等：H5 ios-sheet 同款，灰底圆角顶 + 抓手）

struct BottomSheetScaffold<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @Environment(\.presentationMode) var mode

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(spacing: 0) {
                Capsule().fill(Color(hex: 0xDDDDDD)).frame(width: 36, height: 4).padding(.top, 8)
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                ScrollView(showsIndicators: false) { content }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                Button(action: { mode.wrappedValue.dismiss() }) {
                    Text("知道了").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(Color(hex: 0x1AAD19)).cornerRadius(8)
                }.padding(12)
            }
            .background(Color(hex: 0xF7F7F7).cornerRadius(14, corners: [.topLeft, .topRight]))
        }
    }
}

extension View {
    func cornerRadius(_ r: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: r, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
