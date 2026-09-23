import SwiftUI
import UIKit
import PhotosUI

/// 原生弹窗工具（iOS14 兼容，基于 UIAlertController 挂 keyWindow）
final class PayDialogs {

    private static func topVC() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }

    static func alert(_ title: String, _ message: String) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好的", style: .default))
        vc.present(a, animated: true)
    }

    static func toast(_ message: String) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { a.dismiss(animated: true) }
        vc.present(a, animated: true)
    }

    /// 发红包弹窗
    static func redPacket(isGroup: Bool, done: @escaping (Double, Int, Int, String) -> Void) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: "发红包", message: "拼手气 / 普通红包", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "金额（拼手气=总金额 / 普通=单个金额）"; $0.keyboardType = .decimalPad }
        a.addTextField { $0.placeholder = "红包个数（拼手气必填）"; $0.keyboardType = .numberPad }
        a.addTextField { $0.placeholder = "祝福语（默认 恭喜发财，大吉大利）" }
        a.addAction(UIAlertAction(title: "普通红包", style: .default) { _ in
            let amt = Double(a.textFields?[0].text ?? "") ?? 0
            let num = Int(a.textFields?[1].text ?? "") ?? 1
            let about = a.textFields?[2].text ?? ""
            done(amt, num, 1, about)
        })
        a.addAction(UIAlertAction(title: "拼手气红包", style: .default) { _ in
            let amt = Double(a.textFields?[0].text ?? "") ?? 0
            let num = Int(a.textFields?[1].text ?? "") ?? 1
            let about = a.textFields?[2].text ?? ""
            done(amt, num, 0, about)
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        vc.present(a, animated: true)
    }

    /// 转账弹窗
    static func transfer(qunId: Int64, toId: Int64, done: @escaping (Double, String) -> Void) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: "转账", message: "输入转账金额", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "转账金额（元）"; $0.keyboardType = .decimalPad }
        a.addTextField { $0.placeholder = "备注（选填）" }
        a.addAction(UIAlertAction(title: "转账", style: .default) { _ in
            let amt = Double(a.textFields?[0].text ?? "") ?? 0
            let about = a.textFields?[1].text ?? ""
            done(amt, about)
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        vc.present(a, animated: true)
    }

    /// 充值弹窗：显示名下管理员收款码 + 可填金额 → 通知
    static func recharge(adminName: String, qrcode: String, notify: @escaping (Double) -> Void) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: "充值", message: "向名下管理员「\(adminName)」付款（收款码图片将随后显示）", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "付款金额（选填，方便核对）"; $0.keyboardType = .decimalPad }
        a.addAction(UIAlertAction(title: "我已付款，通知管理员", style: .default) { _ in
            let money = Double(a.textFields?[0].text ?? "") ?? 0
            notify(money)
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        vc.present(a, animated: true)
    }

    /// 提现弹窗：金额 + 从相册选收款码
    static func withdraw(done: @escaping (Double, Data) -> Void) {
        guard let vc = topVC() else { return }
        let a = UIAlertController(title: "群内提现", message: "提现到名下管理员打款，需先上传你的收款码", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "提现金额（元）"; $0.keyboardType = .decimalPad }
        a.addAction(UIAlertAction(title: "从相册选收款码并提交", style: .default) { _ in
            let money = Double(a.textFields?[0].text ?? "") ?? 0
            pickImage { img in
                guard let img = img, let d = img.jpegData(compressionQuality: 0.85) else {
                    toast("未选择收款码")
                    return
                }
                done(money, d)
            }
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
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

    static func packetLog(_ log: JSONObject?) {
        guard let d = log?.data else { toast(log?.msg ?? "网络异常"); return }
        var lines = ["\(d.str("about"))", "已领 \(d.str("got_sum")) / \(d.str("total")) 元"]
        var i = 1
        for o in d.arr {
            lines.append("\(i). \(o.str("nickname"))  ¥\(o.str("amount"))")
            i += 1
            if i > 20 { break }
        }
        alert("红包记录", lines.joined(separator: "\n"))
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
