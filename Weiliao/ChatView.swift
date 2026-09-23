import SwiftUI
import AVFoundation
import Photos

/// 聊天页（群聊 / 好友聊天合一，SwiftUI 原生）
struct ChatView: View {
    var isGroup: Bool
    var id: Int64
    var title: String

    @State var msgs: [Msg] = []
    @State var myUid: Int64 = 0
    @State var myManage = 0
    @State var alllock = 0
    @State var lockText = ""
    @State var input = ""
    @State var lastMid: Int64 = 0
    @State var showMembers = false
    @State var viewer: String? = nil
    @State var showImagePicker = false
    @State var showMemberPicker = false
    @State var members: [MemberRow] = []
    @State var noticePlayer: AVAudioPlayer?

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let recorder = Recorder()

    struct MemberRow: Identifiable {
        var id: Int64
        var nickname: String
        var money: String
    }

    // MARK: - 界面

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(msgs) { m in
                            Bubble(m: m,
                                   onTapImage: { viewer = m.text },
                                   onTapHb: { openPacket(m.packId) },
                                   onTapZz: { WebFallback.open(Api.host + "/Home/Index/transferDetail.html?id=\(m.packId)", title: "转账详情") },
                                   onRecall: { recall(m) })
                                .id(m.mid)
                        }
                    }.padding(8)
                }
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last { withAnimation { proxy.scrollTo(last.mid, anchor: .bottom) } }
                }
            }
            if !lockText.isEmpty {
                Text(lockText).font(.system(size: 13)).foregroundColor(.red).padding(4)
            }
            HStack(spacing: 8) {
                toolBtn("图片") { showImagePicker = true }
                toolBtn("红包") { redPacketDialog() }
                toolBtn("转账") { transferEntry() }
                if isGroup {
                    toolBtn("充值") { rechargeDialog() }
                    toolBtn("提现") { withdrawDialog() }
                }
            }
            HStack(spacing: 8) {
                TextField("说点什么…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(8).background(Color(.systemGray6)).cornerRadius(6)
                Button(action: sendVoiceHint) {
                    Text("按住说话").frame(width: 72, height: 34)
                        .background(Color(.systemGray6)).cornerRadius(6)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !recorder.recording { recorder.start() } }
                        .onEnded { _ in recorder.finish { path, dur in sendVoice(path, dur) } }
                )
                Button(action: sendText) {
                    Text("发送").foregroundColor(.white).frame(width: 60, height: 34)
                        .background(Color(hex: 0x1AAD19)).cornerRadius(6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Color(hex: 0xF5F6F7))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(title)
        .navigationBarItems(trailing: Button("成员") { showMembers = true })
        .sheet(isPresented: $showMembers) { MembersSheet(isGroup: isGroup, id: id, title: title) }
        .sheet(item: Binding(get: { viewer.map { SheetItem(u: $0) } }, set: { viewer = $0?.u })) {
            ImageViewer(url: $0.u)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { ui in
                if let d = ui?.jpegData(compressionQuality: 0.85) {
                    uploadAndSendImage(d)
                }
            }
        }
        .sheet(isPresented: $showMemberPicker) {
            MemberPicker(members: members) { toId in
                showMemberPicker = false
                transferDialog(qunId: id, toId: toId)
            }
        }
        .onAppear { bootstrap() }
        .onReceive(timer) { _ in poll() }
    }

    private func toolBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 13)).foregroundColor(Color(hex: 0x576B95))
                .padding(.horizontal, 10).frame(height: 30)
                .background(Color.white).cornerRadius(6).overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color(.systemGray5))
                )
        }
    }

    private func sendVoiceHint() {}

    // MARK: - 数据

    private func bootstrap() {
        Api.shared.post("/Api/Native/me.html", form: [:]) { r in
            DispatchQueue.main.async {
                if let d = r?.data { myUid = d.long("id") }
            }
        }
        if isGroup {
            Api.shared.post("/Api/Native/groupinfo.html", form: ["qunid": String(id)]) { r in
                DispatchQueue.main.async {
                    if let d = r?.data {
                        myManage = d.int("my_manage")
                        alllock = d.int("alllock")
                        applyLock()
                    }
                }
            }
        }
        firstLoad()
    }

    private var endPath: String { isGroup ? "/Api/Message/getMag.html" : "/Api/Friendmessage/getMag.html" }
    private var sendPath: String { isGroup ? "/Api/Message/send.html" : "/Api/Friendmessage/send.html" }

    private func baseParams() -> [String: String] {
        isGroup ? ["qunid": String(id)] : ["friendid": String(id)]
    }

    private func firstLoad() {
        Api.shared.post(endPath, form: baseParams()) { r in
            if let r = r, r.status == 200 { apply(r, first: true) }
        }
    }

    private func poll() {
        var f = baseParams()
        f["mid"] = String(lastMid)
        Api.shared.post(endPath, form: f) { r in
            if let r = r, r.status == 200 { apply(r, first: false) }
        }
    }

    private func apply(_ r: JSONObject, first: Bool) {
        var batch: [Msg] = []
        for o in r.arr {
            let m = Msg(mid: o.long("mid"), senderId: o.long("id"), nickname: o.str("nickname"),
                        avatar: o.str("headimgurl"), text: o.str("text"), time: o.long("time"),
                        type: o.int("type"), packId: o.long("pack_id"), msgtype: o.str("msgtype"),
                        zzAmount: o.str("zz_amount"), hbDone: o.int("hb_done"), hbMine: o.int("hb_mine"),
                        mine: o.long("id") == myUid)
            if m.mid > lastMid {
                lastMid = m.mid
                batch.append(m)
            }
        }
        DispatchQueue.main.async {
            for m in batch {
                if m.msgtype == "rc" {
                    msgs.removeAll { $0.mid == m.packId }
                    msgs.append(m)
                    continue
                }
                msgs.append(m)
                if !first { maybeVoiceNotice(m) }
            }
            if let lock = (r.raw["lock"] as? Int) { _ = lock }
        }
        if isGroup {
            DispatchQueue.main.async {
                alllock = r.raw["alllock"] as? Int ?? 0
                let lock = r.raw["lock"] as? Int ?? 1
                lockText = alllock == 1 ? "群主已开启全体禁言" : (lock == 0 ? "您已被禁言" : "")
            }
        }
    }

    private func applyLock() {
        // groupinfo 回来时先按 manage 放行，禁言细节以轮询 lock 字段为准
        lockText = alllock == 1 ? "群主已开启全体禁言" : ""
    }

    // MARK: - 发送

    private func sendText() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        input = ""
        var f = baseParams()
        f["text"] = t
        f["type"] = "1"
        Api.shared.post(sendPath, form: f) { r in
            if r?.status != 200 { DispatchQueue.main.async { _ = r?.msg } }
        }
    }

    private func sendVoice(_ path: String, _ dur: Int) {
        var f = baseParams()
        f["text"] = "\(path)|dur=\(max(1, dur))"
        f["type"] = "3"
        Api.shared.post(sendPath, form: f) { _ in }
    }

    private func uploadAndSendImage(_ data: Data) {
        Api.shared.upload("/Home/Index/fileUpload.html", fileData: data, fileName: "img.jpg") { up in
            let path = up?.str("img_path") ?? ""
            guard !path.isEmpty else { return }
            var f = baseParams()
            f["text"] = path
            f["type"] = "2"
            Api.shared.post(sendPath, form: f) { _ in }
        }
    }

    // MARK: - 语音消息/播报

    private func maybeVoiceNotice(_ m: Msg) {
        guard isGroup, myManage == 1 else { return }
        var file: String? = nil
        if m.text.hasPrefix("【充值申请】") { file = "notice_recharge" }
        else if m.text.hasPrefix("【提现申请】") { file = "notice_withdraw" }
        guard let name = file, let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        noticePlayer = try? AVAudioPlayer(contentsOf: url)
        noticePlayer?.play()
    }

    // MARK: - 红包

    private func redPacketDialog() {
        PayDialogs.redPacket(isGroup: isGroup) { amount, num, type, about in
            var f = baseParams()
            f["amount"] = String(format: "%.2f", amount)
            f["num"] = String(num)
            f["type"] = String(type)
            f["about"] = about
            if isGroup { f["qunid"] = String(id) } else { f["friendid"] = String(id) }
            postWithPayPwd("/Home/Index/createPacket.html", f) { _ in }
        }
    }

    private func openPacket(_ packId: Int64) {
        Api.shared.post("/Home/Index/getPacket.html", form: ["id": String(packId)]) { pre in
            if pre?.status == 1 {
                Api.shared.post("/Api/Native/openpacket.html", form: ["id": String(packId)]) { opened in
                    DispatchQueue.main.async {
                        if let d = opened?.data {
                            PayDialogs.alert("已领取", "¥ \(d.str("amount"))\n\(d.str("sender")) 的红包：\(d.str("about"))")
                        } else {
                            PayDialogs.alert("提示", opened?.msg ?? "网络异常")
                        }
                    }
                }
            } else {
                Api.shared.post("/Api/Native/packetlog.html", form: ["id": String(packId)]) { log in
                    DispatchQueue.main.async { PayDialogs.packetLog(log) }
                }
            }
        }
    }

    // MARK: - 转账

    private func transferEntry() {
        if !isGroup {
            transferDialog(qunId: 0, toId: id)
            return
        }
        Api.shared.post("/Api/Message/getQunUser.html", form: ["qunid": String(id)]) { r in
            DispatchQueue.main.async {
                members = (r?.arr ?? []).map { MemberRow(id: $0.long("id"), nickname: $0.str("nickname"), money: $0.str("money")) }
                showMemberPicker = true
            }
        }
    }

    private func transferDialog(qunId: Int64, toId: Int64) {
        PayDialogs.transfer(qunId: qunId, toId: toId) { amount, about in
            var f: [String: String] = ["amount": String(format: "%.2f", amount), "about": about]
            if qunId > 0 {
                f["qunid"] = String(qunId)
                f["toid"] = String(toId)
            } else {
                f["friendid"] = String(toId)
                f["toid"] = String(toId)
            }
            postWithPayPwd("/Home/Index/createTransfer.html", f) { _ in }
        }
    }

    // MARK: - 支付密码闸门

    private func postWithPayPwd(_ path: String, _ form: [String: String], done: @escaping (JSONObject?) -> Void) {
        Api.shared.post(path, form: form) { r in
            if r?.status == 0, r?.raw["need_pwd"] as? Int == 1 {
                if r?.raw["pwd_set"] as? Int == 0 {
                    DispatchQueue.main.async {
                        PayPwdSheet.shared.showSet = true
                    }
                    return
                }
                DispatchQueue.main.async {
                    PayPwdSheet.shared.onPwd = { pwd in
                        var f2 = form
                        f2["paypwd"] = pwd
                        postWithPayPwd(path, f2, done: done)
                    }
                    PayPwdSheet.shared.showAsk = true
                }
                return
            }
            done(r)
            if let info = r?.msg, !info.isEmpty, r?.status == 0 {
                DispatchQueue.main.async { PayDialogs.toast(info) }
            }
        }
    }

    // MARK: - 充值 / 提现

    private func rechargeDialog() {
        Api.shared.post("/Api/Native/rechargeinfo.html", form: ["qunid": String(id)]) { r in
            DispatchQueue.main.async {
                guard let d = r?.data, d.int("has_admin") == 1, d.int("has_code") == 1 else {
                    PayDialogs.toast(r?.data?.str("info") ?? "暂无法充值")
                    return
                }
                PayDialogs.recharge(adminName: d.str("admin_name"), qrcode: d.str("qrcode")) { money in
                    Api.shared.post("/Home/Group/notifyRecharge.html",
                                    form: ["qunid": String(id), "money": String(format: "%.2f", money)]) { nr in
                        DispatchQueue.main.async { PayDialogs.toast(nr?.msg ?? "网络异常") }
                    }
                }
            }
        }
    }

    private func withdrawDialog() {
        PayDialogs.withdraw { money, imageData in
            Api.shared.upload("/Home/Tixian/upload.html", fileData: imageData, fileName: "qr.jpg") { up in
                let url = up?.str("url") ?? ""
                guard url.hasPrefix("/Public/Uploads/withdraw/") else {
                    DispatchQueue.main.async { PayDialogs.toast("收款码上传失败") }
                    return
                }
                Api.shared.post("/Home/Group/withdrawSubmit.html",
                                form: ["qunid": String(id), "money": String(format: "%.2f", money), "qrcode": url]) { r in
                    DispatchQueue.main.async { PayDialogs.toast(r?.msg ?? "网络异常") }
                }
            }
        }
    }

    // MARK: - 撤回

    private func recall(_ m: Msg) {
        guard Int64(Date().timeIntervalSince1970) - m.time <= 120 else { PayDialogs.toast("超过 2 分钟的消息不能撤回"); return }
        var f = baseParams()
        f["mid"] = String(m.mid)
        Api.shared.post(isGroup ? "/Api/Message/recall.html" : "/Api/Friendmessage/recall.html", form: f) { _ in }
    }
}


// MARK: - 成员面板 / 选人

struct MembersSheet: View {
    var isGroup: Bool
    var id: Int64
    var title: String
    @Environment(\.presentationMode) var mode
    @State var rows: [ChatView.MemberRow] = []
    @State var total = ""
    var body: some View {
        NavigationView {
            List {
                if !total.isEmpty {
                    Text("群成员余额合计：¥\(total)（管理员可见）").font(.system(size: 13)).foregroundColor(.orange)
                }
                ForEach(rows) { m in
                    HStack {
                        Text(m.nickname + (m.money.isEmpty ? "" : "  ¥\(m.money)"))
                        Spacer()
                    }
                }
                Button("更多管理（网页）") {
                    WebFallback.open(Api.host + "/Home/Index/index.html?id=\(id)", title: title)
                    mode.wrappedValue.dismiss()
                }
            }
            .navigationTitle("群成员").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("关闭") { mode.wrappedValue.dismiss() })
            .onAppear {
                Api.shared.post("/Api/Message/getQunUser.html", form: ["qunid": String(id)]) { r in
                    DispatchQueue.main.async {
                        rows = (r?.arr ?? []).map { ChatView.MemberRow(id: $0.long("id"), nickname: $0.str("nickname"), money: $0.str("money")) }
                        total = r?.str("money_total") ?? ""
                    }
                }
            }
        }
    }
}

struct MemberPicker: View {
    var members: [ChatView.MemberRow]
    var onPick: (Int64) -> Void
    @Environment(\.presentationMode) var mode
    var body: some View {
        NavigationView {
            List(members) { m in
                Button(action: { onPick(m.id) }) {
                    HStack { Text(m.nickname); Spacer(); Text("¥\(m.money)").foregroundColor(.orange) }
                }
            }
            .navigationTitle("选择转账对象").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("取消") { mode.wrappedValue.dismiss() })
        }
    }
}
