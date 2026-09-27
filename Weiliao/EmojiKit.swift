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

    /// 表情面板固定码点表（与安卓图集同源；v1.14 起不再扫描 Bundle 散 png）
    static let panelEmojis: [String] = [
        "1f308", "1f31e", "1f339", "1f340", "1f349", "1f34e", "1f37a", "1f37b", "1f381",
        "1f382", "1f389", "1f38a", "1f44a", "1f44b", "1f44c", "1f44d", "1f44e", "1f44f",
        "1f48a", "1f48e", "1f4a3", "1f4a4", "1f4a8", "1f4aa", "1f4af", "1f4b0", "1f525",
        "1f590", "1f596", "1f600", "1f601", "1f602", "1f603", "1f604", "1f605", "1f606",
        "1f607", "1f609", "1f60a", "1f60b", "1f60c", "1f60d", "1f60e", "1f60f", "1f610",
        "1f611", "1f612", "1f613", "1f614", "1f615", "1f616", "1f617", "1f618", "1f619",
        "1f61a", "1f61b", "1f61c", "1f61d", "1f61e", "1f61f", "1f620", "1f621", "1f622",
        "1f623", "1f624", "1f625", "1f626", "1f627", "1f628", "1f629", "1f62a", "1f62b",
        "1f62c", "1f62d", "1f62e", "1f62f", "1f630", "1f631", "1f632", "1f633", "1f634",
        "1f635", "1f636", "1f637", "1f641", "1f642", "1f643", "1f644", "1f64c", "1f64f",
        "1f910", "1f911", "1f912", "1f914", "1f915", "1f917", "1f918", "1f919", "1f91b",
        "1f91c", "1f91d", "1f91e", "1f91f", "1f920", "1f922", "1f923", "1f924", "1f925",
        "1f92b", "1f92d", "1f92e", "1f92f", "1f942", "1f973", "1f97a", "1f9d0",
    ]

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
