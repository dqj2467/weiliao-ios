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
    var status: Int { raw["status"] as? Int ?? 0 }
    var msg: String { raw["msg"] as? String ?? raw["info"] as? String ?? "" }
    var data: JSONObject? { (raw["data"] as? [String: Any]).map { JSONObject($0) } }
    var list: [JSONObject] {
        guard let arr = raw["data"] as? [[String: Any]] ?? (raw["data"] as? [String: Any])?["list"] as? [[String: Any]] else { return [] }
        return arr.map { JSONObject($0) }.compactMap { $0 }
    }
    var arr: [JSONObject] {
        guard let a = raw["data"] as? [[String: Any]] else { return [] }
        return a.compactMap { JSONObject($0) }
    }
    func int(_ k: String) -> Int { raw[k] as? Int ?? Int(raw[k] as? Double ?? 0) }
    func long(_ k: String) -> Int64 { raw[k] as? Int64 ?? Int64(raw[k] as? Int ?? 0) }
    func str(_ k: String) -> String { raw[k] as? String ?? "" }
    func dict(_ k: String) -> JSONObject? { (raw[k] as? [String: Any]).map { JSONObject($0) } }
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
    var id: Int64 { mid }
    var mine: Bool
}
