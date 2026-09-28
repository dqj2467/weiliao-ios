import SwiftUI
import AVFoundation
import AudioToolbox
import TXLiteAVSDK_TRTC

// ============================================================
// 1v1 语音通话（2026-09-28，腾讯云 TRTC，v1.22）
//  - 信令走 HTTP 轮询（/Api/Call/*），与安卓同口径
//  - CallManager：全局单例，3 秒轮询来电；RootContainer 监听 incoming 弹全屏通话页
//  - CallPage：role caller（呼叫中）/ callee（来电）→ talking；静音/免提/挂断
//  - iOS 限制：APP 内接听（无 VoIP push），锁屏来电二期待 Apple 开发者账号配置
// ============================================================

struct CallInfo: Equatable, Identifiable {
    let id = UUID()
    var callid: Int64 = 0
    var roomid: Int64 = 0
    var peerId: Int64 = 0
    var peerName: String = ""
    var peerFace: String = ""
    var appid: String = ""
    var sig: String = ""
}

final class CallManager: ObservableObject {
    static let shared = CallManager()
    @Published var incoming: CallInfo? = nil       // 非空 → 独立窗口弹来电
    @Published var pendingReqs: Int = 0            // 好友申请待处理数（通讯录「新的朋友」角标）
    var active = false                              // CallPage 挂载中（不重复弹/不重复轮）
    private var myUid: Int64 = 0
    private var t: Timer?

    private init() {
        t = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollTick()
        }
    }

    private func pollTick() {
        guard !active, incoming == nil else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        Api.shared.post("/Api/Call/poll.html", form: [:]) { r in
            guard let r = r, r.status == 200, let d = r.data else { return }
            // 好友申请待处理数（poll 捎带）
            let reqs = d.int("reqs")
            DispatchQueue.main.async {
                if reqs > self.pendingReqs && reqs > 0 { PayDialogs.toast("有新的好友申请") }
                self.pendingReqs = max(0, reqs)
            }
            guard d.str("type") == "invite" else { return }
            guard !self.active, self.incoming == nil else { return }
            let peer = d.dict("peer")
            DispatchQueue.main.async {
                self.incoming = CallInfo(callid: d.long("callid"),
                                         roomid: d.long("roomid"),
                                         peerId: peer?.long("id") ?? 0,
                                         peerName: peer?.str("nickname") ?? "",
                                         peerFace: peer?.str("headimgurl") ?? "",
                                         appid: d.str("sdkappid"),
                                         sig: "")
                CallWindowMgr.sync()
            }
        }
    }

    // ---------- 好友申请 API ----------

    func sendFriendReq(toUid: Int64, note: String, completion: @escaping (Bool, String) -> Void) {
        Api.shared.post("/Api/Friendreq/send.html",
                        form: ["to_uid": String(toUid), "note": note]) { r in
            completion(r?.status == 200, r?.str("msg") ?? "网络异常")
        }
    }

    struct FriendReq: Identifiable {
        let id: Int64
        var status: Int
        var byMe: Bool
        var name: String
        var face: String
        var note: String
        var timeText: String
    }

    func loadFriendReqs(completion: @escaping ([FriendReq]) -> Void) {
        Api.shared.post("/Api/Friendreq/lists.html", form: [:]) { r in
            var out: [FriendReq] = []
            if let r = r, r.status == 200, let d = r.data {
                for row in d.arrIn("incoming") {
                    let f = row.dict("from")
                    out.append(FriendReq(id: row.long("id"), status: 0, byMe: false,
                                         name: f?.str("nickname") ?? "", face: f?.str("headimgurl") ?? "",
                                         note: row.str("note"), timeText: ""))
                }
                for row in d.arrIn("handled") {
                    let peer = row.int("by_me") == 1 ? row.dict("from") : row.dict("to")
                    out.append(FriendReq(id: row.long("id"), status: row.int("status"), byMe: row.int("by_me") == 1,
                                         name: peer?.str("nickname") ?? "", face: peer?.str("headimgurl") ?? "",
                                         note: "", timeText: ""))
                }
            }
            DispatchQueue.main.async {
                self.pendingReqs = out.filter { $0.status == 0 }.count
                completion(out)
            }
        }
    }

    func handleFriendReq(id: Int64, op: Int, completion: @escaping (Bool, String) -> Void) {
        Api.shared.post("/Api/Friendreq/handle.html",
                        form: ["id": String(id), "op": String(op)]) { r in
            completion(r?.status == 200, r?.str("msg") ?? "网络异常")
        }
    }

    /// 主叫入口（聊天页）：invite 拿 callid/roomid/sig 后回调
    func invite(peerId: Int64, completion: @escaping (CallInfo?, String) -> Void) {
        Api.shared.post("/Api/Call/invite.html", form: ["to_uid": String(peerId)]) { r in
            if let r = r, r.status == 200, let d = r.data {
                let peer = d.dict("peer")
                let info = CallInfo(callid: d.long("callid"),
                                    roomid: d.long("roomid"),
                                    peerId: peerId,
                                    peerName: peer?.str("nickname") ?? "",
                                    peerFace: peer?.str("headimgurl") ?? "",
                                    appid: d.str("sdkappid"),
                                    sig: d.str("usersig"))
                completion(info, "")
            } else {
                completion(nil, r?.str("msg") ?? "网络异常")
            }
        }
    }

    func ensureUid() {
        if myUid > 0 { return }
        Api.shared.post("/Api/Native/me.html", form: [:]) { r in
            if let d = r?.data { self.myUid = d.long("id") }
        }
    }

    func uid() -> Int64 { return myUid }
}

// ============================================================
// 通话页
// ============================================================

struct CallPage: View {
    enum Role { case caller, callee }
    let role: Role
    @State var info: CallInfo
    var onClose: () -> Void

    @State var phase = 0                 // 0 来电/呼叫中  1 通话中  2 已结束
    @State var tip = ""                  // 结束提示
    @State var talkSec = 0
    @State var micOn = true
    @State var speaker = false
    @State var ringPlayer: AVAudioPlayer?   // 被叫振铃：微信式铃声循环
    @State var vibTimer: Timer?
    @State var stateTimer: Timer?
    @State var secTimer: Timer?
    var cloud = CloudBox()

    var body: some View {
        ZStack {
            Color(hex: 0x26292E).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("微聊语音通话").font(.system(size: 13)).foregroundColor(Color(hex: 0x88FFFFFF))
                    .padding(.top, 40)
                Avatar(url: info.peerFace, fallback: info.peerName.isEmpty ? "友" : info.peerName, size: 108)
                    .padding(.top, 52)
                Text(info.peerName.isEmpty ? "微聊用户" : info.peerName)
                    .font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
                    .padding(.top, 18)
                Group {
                    if phase == 1 {
                        Text(String(format: "通话中  %02d:%02d", talkSec / 60, talkSec % 60))
                            .foregroundColor(Color(hex: 0xCCFFFFFF))
                    } else if !tip.isEmpty {
                        Text(tip).foregroundColor(Color(hex: 0x99FFFFFF))
                    } else if role == .caller {
                        Text("等待对方接听…").foregroundColor(Color(hex: 0x99FFFFFF))
                    } else {
                        Text("来电邀请").foregroundColor(Color(hex: 0x99FFFFFF))
                    }
                }.font(.system(size: 14)).padding(.top, 8)

                Spacer()

                if phase == 0 && role == .callee && tip.isEmpty {
                    // 来电：拒接 + 接听
                    HStack(spacing: 72) {
                        circleBtn("拒接", color: Color(hex: 0xFFFF4E43)) { reject() }
                        circleBtn("接听", color: Color(hex: 0x07C160)) { accept() }
                    }.padding(.bottom, 60)
                } else if phase == 1 {
                    // 通话中：静音 / 免提 / 挂断
                    HStack(spacing: 30) {
                        circleBtn(micOn ? "静音" : "已静音", color: Color(hex: 0x33FFFFFF)) {
                            micOn.toggle()
                            cloud.trtc?.muteLocalAudio(!micOn)
                        }
                        circleBtn(speaker ? "听筒" : "免提", color: Color(hex: 0x33FFFFFF)) {
                            speaker.toggle()
                            // 【12.x】setAudioRoute 已移到 DeviceManager，枚举 TXAudioRoute
                            cloud.trtc?.getDeviceManager().setAudioRoute(
                                speaker ? TXAudioRoute.speakerphone : TXAudioRoute.earpiece)
                        }
                        circleBtn("挂断", color: Color(hex: 0xFFFF4E43)) { hangup() }
                    }.padding(.bottom, 60)
                } else {
                    // 结束：只剩一个红色按钮方便关
                    circleBtn("关闭", color: Color(hex: 0xFFFF4E43)) { cleanup(); onClose() }
                        .padding(.bottom, 60)
                }
            }
        }
        .onAppear { start() }
        .onDisappear { stopTimers() }
    }

    // ---------- 启动 / 状态机 ----------

    private func start() {
        CallManager.shared.active = true
        CallManager.shared.ensureUid()
        if role == .caller {
            enterRoom()
            startStatePoll()
        } else {
            startRing()          // 被叫：微信式来电铃声+震动
            startRingPoll()      // 接听前轮询对方取消
        }
    }

    // ---------- 来电铃声 ----------

    private func startRing() {
        if let url = Bundle.main.url(forResource: "ring", withExtension: "wav") {
            ringPlayer = try? AVAudioPlayer(contentsOf: url)
            ringPlayer?.numberOfLoops = -1
            ringPlayer?.play()
        }
        vibTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func stopRing() {
        ringPlayer?.stop(); ringPlayer = nil
        vibTimer?.invalidate(); vibTimer = nil
    }

    private func accept() {
        Api.shared.post("/Api/Call/answer.html", form: ["callid": String(info.callid)]) { r in
            if let r = r, r.status == 200, let d = r.data {
                info.roomid = d.long("roomid")
                info.sig = d.str("usersig")
                info.appid = d.str("sdkappid")
                DispatchQueue.main.async { self.enterRoom() }
            } else {
                DispatchQueue.main.async {
                    self.tip = "通话已失效"
                    self.phase = 2
                }
            }
        }
    }

    private func reject() {
        Api.shared.post("/Api/Call/reject.html", form: ["callid": String(info.callid)]) { _ in }
        end("已拒接")
    }

    private func hangup() {
        Api.shared.post("/Api/Call/hangup.html", form: ["callid": String(info.callid)]) { _ in }
        end(phase == 1 ? "通话结束" : "已取消")
    }

    private func end(_ t: String) {
        phase = 2
        tip = t
        cloud.leave()
        stopTimers()
    }

    // ---------- 信令轮询 ----------

    private func startStatePoll() {
        stateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard phase != 2 else { return }
            Api.shared.post("/Api/Call/state.html", form: ["callid": String(info.callid)]) { r in
                guard let r = r, r.status == 200, let d = r.data else { return }
                let st = d.int("status")
                if let peer = d.dict("peer") {
                    DispatchQueue.main.async {
                        info.peerId = peer.long("id")
                        info.peerName = peer.str("nickname")
                        info.peerFace = peer.str("headimgurl")
                    }
                }
                DispatchQueue.main.async {
                    switch st {
                    case 2: end("对方已拒接")
                    case 3: end("无人接听")
                    case 4: end("通话结束")
                    case 1: if phase == 0 { tip = "已接通，正在连接…" }
                    default: break
                    }
                }
            }
        }
    }

    private func startRingPoll() {
        stateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard phase == 0, role == .callee else { return }
            Api.shared.post("/Api/Call/state.html", form: ["callid": String(info.callid)]) { r in
                guard let r = r, r.status == 200, let d = r.data else { return }
                if d.int("status") == 3 {
                    DispatchQueue.main.async { end("对方已取消") }
                }
            }
        }
    }

    private func stopTimers() {
        stateTimer?.invalidate(); stateTimer = nil
        secTimer?.invalidate(); secTimer = nil
        stopRing()
    }

    // ---------- TRTC ----------

    private func enterRoom() {
        guard CallManager.shared.uid() > 0, info.roomid > 0, !info.appid.isEmpty, !info.sig.isEmpty else { return }
        cloud.enter(appid: UInt32(info.appid) ?? 0,
                    uid: String(CallManager.shared.uid()),
                    sig: info.sig,
                    roomid: UInt32(info.roomid)) { peerAudio in
            if peerAudio { DispatchQueue.main.async { toTalk() } }
        }
        // 计时器在音频回调里启动
    }

    private func toTalk() {
        guard phase != 1 else { return }
        stopRing()
        phase = 1
        talkSec = 0
        secTimer?.invalidate()
        secTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            talkSec += 1
        }
    }

    private func cleanup() {
        cloud.leave()
        stopTimers()
        CallManager.shared.active = false
    }

    // ---------- 小控件 ----------

    private func circleBtn(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        // ★ZStack 显式居中：真机上出现过文字偏左，改圆+文字分层绝对居中
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Text(label).font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 64, height: 64)
        }.buttonStyle(.plain)
    }
}

/// TRTC 云实例盒（struct 里持有 class 引用，随 CallPage 生命周期）
/// 【12.x】iOS SDK 监听协议是 TRTCCloudDelegate（不是安卓的 Listener），经 delegate 属性设置
/// 注意：不能 private —— CallPage 依赖 memberwise init，存储属性必须 internal
final class CloudBox: NSObject, TRTCCloudDelegate {
    var trtc: TRTCCloud?
    private var onPeerAudio: ((Bool) -> Void)?

    func enter(appid: UInt32, uid: String, sig: String, roomid: UInt32, onPeerAudio: @escaping (Bool) -> Void) {
        guard trtc == nil else { return }
        self.onPeerAudio = onPeerAudio
        let c = TRTCCloud.sharedInstance()
        c.delegate = self
        let p = TRTCParams()
        p.sdkAppId = appid
        p.userId = uid
        p.userSig = sig
        p.roomId = roomid
        p.role = .anchor
        trtc = c
        c.enterRoom(p, appScene: .audioCall)
        c.getDeviceManager().setAudioRoute(.earpiece)
    }

    func leave() {
        guard let c = trtc else { return }
        c.stopLocalAudio()
        c.exitRoom()
        TRTCCloud.destroySharedInstance()
        trtc = nil
    }

    // MARK: - TRTCCloudDelegate（@objc 协议方法，不加 override）
    func onEnterRoom(_ result: Int) {
        if result >= 0 { trtc?.startLocalAudio(.default) }
    }

    func onUserAudioAvailable(_ userId: String, available: Bool) {
        if available { onPeerAudio?(true) }
    }

    func onRemoteUserLeaveRoom(_ userId: String, reason: Int) {
        onPeerAudio?(false)
    }

    func onError(_ errCode: Int32, errMsg: String?, extraInfo: [AnyHashable: Any]?) {
        print("TRTC err \(errCode) \(errMsg ?? "")")
    }
}

// ============================================================
// 来电独立窗口（v1.22）：沿用支付密码 PayPwdWindowMgr 的方案 ——
// fullScreenCover 挂同一视图会互相顶掉（v1.15 教训），来电必须盖过一切弹层，独立 UIWindow 最稳
// ============================================================

final class CallWindowMgr {
    static var win: UIWindow?

    static func sync() {
        let mgr = CallManager.shared
        if let info = mgr.incoming {
            guard win == nil else { return }
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene = scene else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 2
            w.backgroundColor = .clear
            let page = CallPage(role: .callee, info: info, onClose: {
                mgr.incoming = nil
                CallWindowMgr.sync()
            })
            w.rootViewController = UIHostingController(rootView: page)
            w.makeKeyAndVisible()
            win = w
        } else {
            win?.isHidden = true
            win?.rootViewController = nil
            win = nil
        }
    }
}

/// 挂在 RootContainer 上的触发器（观察 incoming 变化同步独立窗口）
struct CallIncomingOverlay: View {
    @ObservedObject var mgr = CallManager.shared
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { CallWindowMgr.sync() }
            .onChange(of: mgr.incoming) { _ in CallWindowMgr.sync() }
    }
}
