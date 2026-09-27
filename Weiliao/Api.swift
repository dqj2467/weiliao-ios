import Foundation

/// 网络层：URLSession + 共享 CookieStorage（PHPSESSID 自动携带，与网页版同一会话体系）
final class Api {
    static let host = "http://weiliao.tbb.wiki:8082"
    static let shared = Api()
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 8
        session = URLSession(configuration: cfg)
    }

    static func json(_ obj: [String: Any]) -> JSONObject? {
        (try? JSONSerialization.data(withJSONObject: obj)).flatMap { JSONObject($0) }
    }

    // MARK: - 请求

    func post(_ path: String, form: [String: String], done: @escaping (JSONObject?) -> Void) {
        guard let url = URL(string: Api.host + path) else { done(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let body = form.map { "\($0.key)=\(urlEncode($0.value))" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        exec(req, done)
    }

    func upload(_ path: String, fileData: Data, fileName: String, done: @escaping (JSONObject?) -> Void) {
        guard let url = URL(string: Api.host + path) else { done(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        let boundary = "wl" + UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        exec(req, done)
    }

    func fetchImage(_ path: String, done: @escaping (Data?) -> Void) {
        let abs = path.hasPrefix("http") ? path : Api.host + path
        guard let url = URL(string: abs) else { done(nil); return }
        session.dataTask(with: url) { d, _, _ in done(d) }.resume()
    }

    private func exec(_ req: URLRequest, _ done: @escaping (JSONObject?) -> Void) {
        // 失败自动重试一次：手机切网后连接池里的旧连接可能挂死，重试走新连接即恢复（与安卓 v5.8+ 同策略）
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard err == nil, let d = data, !d.isEmpty else {
                self?.session.dataTask(with: req) { d2, _, err2 in
                    guard err2 == nil, let d2 = d2, !d2.isEmpty else { done(nil); return }
                    done(JSONObject(d2))
                }.resume()
                return
            }
            done(JSONObject(d))
        }.resume()
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// 轻量 JSON 包装
struct JSONObject {
    let raw: [String: Any]
    init?(_ data: Data) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        raw = o
    }
    init?(dict: [String: Any]) { raw = dict }
    var status: Int { int("status") }
    var msg: String { raw["msg"] as? String ?? raw["info"] as? String ?? "" }
    var data: JSONObject? { (raw["data"] as? [String: Any]).flatMap { JSONObject(dict: $0) } }
    var list: [JSONObject] {
        guard let arr = raw["data"] as? [[String: Any]] ?? (raw["data"] as? [String: Any])?["list"] as? [[String: Any]] else { return [] }
        return arr.map { JSONObject(dict: $0) }.compactMap { $0 }
    }
    var arr: [JSONObject] {
        guard let a = raw["data"] as? [[String: Any]] else { return [] }
        return a.compactMap { JSONObject(dict: $0) }
    }
    /// data 里的 list 数组（NativeController 口径：data:{list:[...]}）
    var listItems: [JSONObject] {
        guard let a = raw["list"] as? [[String: Any]] else { return [] }
        return a.compactMap { JSONObject(dict: $0) }
    }
    /// ★v1.14 全类型兜底：PHP/PDO 返回的 JSON 数字列全是字符串（mid:"123"），
    /// 旧实现 as? Int 全部变 0 → 消息不入列/uid=0/时间=0，炸掉 iOS 端一切显示。
    private func num(_ k: String) -> Double {
        switch raw[k] {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let i64 as Int64: return Double(i64)
        case let b as Bool: return b ? 1 : 0
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }
    func int(_ k: String) -> Int { Int(num(k)) }
    func long(_ k: String) -> Int64 { Int64(num(k)) }
    func str(_ k: String) -> String { raw[k] as? String ?? "" }
    func dict(_ k: String) -> JSONObject? { (raw[k] as? [String: Any]).flatMap { JSONObject(dict: $0) } }
}

/// 消息模型
struct Msg: Identifiable {
    var mid: Int64
    var senderId: Int64
    var nickname: String
    var avatar: String
    var text: String
    var time: Int64
    var type: Int          // 1 文字 2 图片 3 语音
    var packId: Int64
    var msgtype: String    // "" hb zz rc
    var zzAmount: String
    var hbDone: Int
    var hbMine: Int
    var money: String      // 发送者本群群钱包余额（getMag 下发，气泡头像下方显示）
    var id: Int64 { mid }
    var mine: Bool
}
