import UIKit
import SwiftUI

/// 表情引擎（对齐安卓 v5.47：按码点处理，修复「正则匹配不到代理对→原始4字节入库→utf8截断成空」的历史坑）
enum Emo {

    // MARK: - 发送前编码：增补平面(4字节)emoji → &#x...; 实体；BMP 符号区同 H5 emojEncode 口径

    static func encode(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = String(); out.reserveCapacity(s.count + 16)
        let sc = Array(s.unicodeScalars)
        var i = 0
        while i < sc.count {
            let v = sc[i].value
            if v >= 0x10000 {                                  // 增补平面（含所有 4 字节 emoji）
                out += "&#x" + String(v, radix: 16) + ";"
                i += 1
                continue
            }
            if (0x2190...0x2BFF).contains(v) || v == 0x3030 || v == 0x303D
                || v == 0x3297 || v == 0x3299 {                // BMP 符号区（H5 同款范围）
                out += "&#x" + String(v, radix: 16) + ";"
                i += 1
                if i < sc.count && sc[i].value == 0xFE0F { i += 1 }   // 吃掉后随变体选择符
                continue
            }
            out.unicodeScalars.append(sc[i])
            i += 1
        }
        return out
    }

    // MARK: - 解码：&#x hex; / &# dec; → 字符

    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = String(); out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "&", let sc = s.index(i, offsetBy: 2, limitedBy: s.endIndex), sc < s.endIndex {
                let next = s[s.index(after: i)]
                var value: Int? = nil
                var j = s.index(after: i)
                if next == "x" || next == "X" {
                    j = s.index(after: j)
                    var hex = 0
                    while j < s.endIndex, let d = s[j].hexDigitValue {
                        hex = hex * 16 + d
                        j = s.index(after: j)
                    }
                    if j < s.endIndex && s[j] == ";" && hex > 0 { value = hex }
                } else if next == "#" {
                    var dec = 0
                    while j < s.endIndex, let d = s[j].wholeNumberValue, d >= 0, d <= 9 {
                        dec = dec * 10 + d
                        j = s.index(after: j)
                    }
                    if j < s.endIndex && s[j] == ";" && dec > 0 { value = dec }
                }
                if let v = value, let us = Unicode.Scalar(v) {
                    out.unicodeScalars.append(us)
                    i = s.index(after: j)
                    continue
                }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    // MARK: - 表情图（与安卓 emojiBmp 同源：Bundle 根目录 <hex>.png，121 张）

    private static var imgCache: [String: UIImage?] = [:]

    static func isEmojiCp(_ v: UInt32) -> Bool {
        (v >= 0x1F000 && v <= 0x1FAFF) || (v >= 0x2190 && v <= 0x2BFF)
            || v == 0x3030 || v == 0x303D || v == 0x3297 || v == 0x3299
    }

    static func image(_ hex: String) -> UIImage? {
        if let cached = imgCache[hex] { return cached }
        let img = UIImage(named: hex)
        imgCache[hex] = img
        return img
    }

    /// 文本 → 富文本：emoji 码点替换为内联图（无图资源时按普通文字渲染，跳过 FE0F/ZWJ）
    static func attributed(_ s: String, size: CGFloat, color: UIColor) -> NSAttributedString {
        let text = decode(s)
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let base: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let sc = Array(text.unicodeScalars)
        var i = 0
        while i < sc.count {
            let v = sc[i].value
            if v == 0xFE0F || v == 0x200D { i += 1; continue }
            if isEmojiCp(v) {
                let hex = String(v, radix: 16)
                if let img = image(hex) {
                    let at = NSTextAttachment()
                    at.image = img
                    at.bounds = CGRect(x: 0, y: -2, width: size + 4, height: size + 4)
                    out.append(NSAttributedString(attachment: at))
                    i += 1
                    if i < sc.count && sc[i].value == 0xFE0F { i += 1 }
                    continue
                }
            }
            var run = String.UnicodeScalarView()
            while i < sc.count {
                let v2 = sc[i].value
                if v2 != 0xFE0F && v2 != 0x200D && isEmojiCp(v2) { break }
                run.append(sc[i])
                i += 1
            }
            out.append(NSAttributedString(string: String(run), attributes: base))
        }
        return out
    }

    // MARK: - 表情面板列表（Bundle 内全部 <hex>.png，按码点排序，与安卓同图集）

    static let panelEmojis: [String] = {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) else { return [] }
        var hexes: [Int] = []
        for u in urls {
            let name = u.deletingPathExtension().lastPathComponent
            if name.range(of: "^[0-9a-f]{4,6}$", options: .regularExpression) != nil,
               let v = Int(name, radix: 16), isEmojiCp(UInt32(v)) {
                hexes.append(v)
            }
        }
        return hexes.sorted().map { String($0, radix: 16) }
    }()

    /// 码点 → 面板可插入的字符
    static func char(_ hex: String) -> String? {
        guard let v = UInt32(hex, radix: 16), let us = Unicode.Scalar(v) else { return nil }
        return String(us)
    }
}

// MARK: - 富文本标签（UILabel 包装：iOS14 上 SwiftUI Text 渲染不了 NSTextAttachment 内联图）

struct EmoLabel: UIViewRepresentable {
    var text: String
    var size: CGFloat = 15
    var color: UIColor = .black

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        return l
    }
    func updateUIView(_ l: UILabel, context: Context) {
        l.attributedText = Emo.attributed(text, size: size, color: color)
    }
}
