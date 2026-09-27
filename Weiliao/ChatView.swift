import SwiftUI
import AVFoundation
import Photos
import PhotosUI

/// 原生聊天页（1:1 移植安卓 ChatActivity：表情内联渲染、红包/转账气泡、支付密码闸门、
/// 红包打开走 H5 页（安卓 v5.32 同流程）、红包状态回填（v5.35 同款））

struct ChatScreen: View {
    var isGroup: Bool
    var chatId: Int64
    var title: String
    var onClosed: () -> Void = {}

    @Environment(\.presentationMode) var mode
    @ObservedObject var router = WebFallback.shared
    @ObservedObject var pwd = PayPwdSheet.shared

    @State var msgs: [Msg] = []
    @State var myUid: Int64 = 0
    @State var myManage = 0
    @State var lockText = ""
    @State var input = ""
    @State var lastMid: Int64 = 0
    @State var showMembers = false
    @State var viewer: String? = nil
    @State var showImagePicker = false
    @State var showMemberPicker = false
    @State var showEmojiPanel = false
    @State var members: [ChatScreen.MemberRow] = []
    @State var noticePlayer: AVAudioPlayer?

    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    struct MemberRow: Identifiable {
        var id: Int64
        var nickname: String
        var money: String
    }

    // MARK: - 界面

    var body: some View {
        VStack(spacing: 0) {
            // 原生头部栏（安卓同款：返回箭头 + 标题 + 群成员）
            HStack(spacing: 0) {
                Button(action: { mode.wrappedValue.dismiss(); onClosed() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: 0x262626))
                        .frame(width: 40, height: 44)
                }
                Spacer()
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(hex: 0x262626))
                Spacer()
                if isGroup {
                    Button(action: { showMembers = true }) {
                        Image(systemName: "person.2")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: 0x576B95))
                            .frame(width: 40, height: 44)
                    }
                } else {
                    Color.clear.frame(width: 40, height: 44)
                }
            }
            .background(Color(hex: 0xEDEDED))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(msgs) { m in
                            Bubble(m: m, mine: m.senderId == myUid,
                                   onTapImage: { viewer = m.text },
                                   onTapHb: { openPacket(m.packId) },
                                   onTapZz: { openTransferDetail(m.packId) },
                                   onRecall: { recall(m) })
                                .id(m.mid)
                        }
                    }.padding(8)
                }
                .onChange(of: msgs.count) { _ in
                    if let last = msgs.last {
                        withAnimation { proxy.scrollTo(last.mid, anchor: .bottom) }
                    }
                }
            }

            if !lockText.isEmpty {
                Text(lockText).font(.system(size: 13)).foregroundColor(.red).padding(4)
            }

            // 工具行（群：红包/转账/充值/提现）
            if isGroup {
                HStack(spacing: 8) {
                    toolBtn("红包", icon: "hb") { redPacketDialog() }
                    toolBtn("转账", icon: "h5ico_sendimg") { transferEntry() }
                    toolBtn("充值", icon: "uc1") { rechargeDialog() }
                    toolBtn("提现", icon: "uc2") { withdrawDialog() }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }

            // 输入区
            HStack(spacing: 8) {
                Button(action: { showEmojiPanel.toggle() }) {
                    Image("h5ico_emoji").resizable().scaledToFit().frame(width: 26, height: 26)
                }
                Button(action: { showImagePicker = true }) {
                    Image("h5ico_sendimg").resizable().scaledToFit().frame(width: 26, height: 26)
                }
                TextField("说点什么…", text: $input)
                    .font(.system(size: 15))
                    .padding(8).background(Color(.systemGray6)).cornerRadius(6)
                Button(action: sendText) {
                    Text("发送").font(.system(size: 14)).foregroundColor(.white)
                        .frame(width: 58, height: 34)
                        .background(Color(hex: 0x1AAD19)).cornerRadius(6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)

            if showEmojiPanel {
                emojiPanel
            }
        }
        .background(Color(hex: 0xF5F6F7))
        .background(EmptyView().sheet(item: Binding(get: { viewer.map { SheetItem(u: $0) } },
                                                    set: { viewer = $0?.u })) {
            ImageViewer(url: viewer ?? "")
        })
        .background(EmptyView().sheet(isPresented: $showImagePicker) {
            ImagePicker { ui in
                if let d = ui?.jpegData(compressionQuality: 0.85) { uploadAndSendImage(d) }
            }
        })
        .background(EmptyView().sheet(isPresented: $showMembers) {
            MembersSheet(isGroup: isGroup, id: chatId, title: title)
        })
        .background(EmptyView().sheet(isPresented: $showMemberPicker) {
            MemberPicker(members: members) { toId in
                showMemberPicker = false
                transferDialog(qunId: isGroup ? chatId : 0, toId: isGroup ? toId : chatId)
            }
        })
        .background(EmptyView().sheet(item: $router.item) { item in
            WebViewScreen(url: item.url, title: item.title)
        })
        .background(EmptyView().sheet(isPresented: $pwd.showAsk) { PayPwdAskView() })
        .background(EmptyView().sheet(isPresented: $pwd.showSet) { PayPwdSetView() })
        .onAppear { bootstrap() }
        .onReceive(timer) { _ in poll() }
    }

    private func toolBtn(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(icon).resizable().scaledToFit().frame(width: 16, height: 16)
                Text(label).font(.system(size: 13)).foregroundColor(Color(hex: 0x576B95))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(Color.white).cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(.systemGray5)))
        }.buttonStyle(.plain)
    }

    // MARK: - 表情面板

    private var emojiPanel: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 10) {
                ForEach(Emo.panelEmojis, id: \.self) { hex in
                    Button(action: {
                        if let ch = Emo.char(hex) { input += ch }
                    }) {
                        if let img = Emo.image(hex) {
                            Image(uiImage: img).resizable().scaledToFit().frame(width: 30, height: 30)
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(height: 220)
        .background(Color(hex: 0xF7F7F7))
    }

    // MARK: - 数据

    private func bootstrap() {
        Api.shared.post("/Api/Native/me.html", form: [:]) { r in
            DispatchQueue.main.async {
                if let d = r?.data { myUid = d.long("id") }
            }
        }
        firstLoad()
    }

    private var endPath: String { isGroup ? "/Api/Message/getMag.html" : "/Api/Friendmessage/getMag.html" }
    private var sendPath: String { isGroup ? "/Api/Message/send.html" : "/Api/Friendmessage/send.html" }

    private func baseParams() -> [String: String] {
        isGroup ? ["qunid": String(chatId)] : ["friendid": String(chatId)]
    }

    private func firstLoad() {
        Api.shared.post(endPath, form: baseParams()) { r in
            if let r = r, r.status == 200 {
                apply(r, first: true)
                refreshPacketStates()
            }
        }
    }

    private func poll() {
        var f = baseParams()
        f["mid"] = String(lastMid)
        Api.shared.post(endPath, form: f) { r in
            if let r = r, r.status == 200 { apply(r, first: false) }
        }
    }

    private func parseMsg(_ o: JSONObject) -> Msg {
        Msg(mid: o.long("mid"), senderId: o.long("id"), nickname: o.str("nickname"),
            avatar: o.str("headimgurl"), text: o.str("text"), time: o.long("time"),
            type: o.int("type"), packId: o.long("pack_id"), msgtype: o.str("msgtype"),
            zzAmount: o.str("zz_amount"), hbDone: o.int("hb_done"), hbMine: o.int("hb_mine"),
            mine: false)
    }

    private func apply(_ r: JSONObject, first: Bool) {
        var batch: [Msg] = []
        for o in r.arr {
            let m = parseMsg(o)
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
                voiceNotice(m)
            }
        }
        if isGroup {
            let alllock = r.raw["alllock"] as? Int ?? 0
            let lock = r.raw["lock"] as? Int ?? 1
            DispatchQueue.main.async {
                lockText = alllock == 1 ? "群主已开启全体禁言" : (lock == 0 ? "您已被禁言" : "")
            }
        }
    }

    /// 红包状态回填（安卓 v5.35 refreshPacketStates 同款：getMag mid=0 拉最新一批更新 hb_done/hb_mine）
    private func refreshPacketStates() {
        var f = baseParams()
        f["mid"] = "0"
        Api.shared.post(endPath, form: f) { r in
            guard let r = r, r.status == 200 else { return }
            let latest = (r.arr.suffix(10)).map { parseMsg($0) }
            DispatchQueue.main.async {
                for nm in latest {
                    if let idx = msgs.firstIndex(where: { $0.mid == nm.mid }) {
                        msgs[idx].hbDone = nm.hbDone
                        msgs[idx].hbMine = nm.hbMine
                    }
                }
            }
        }
    }

    private func voiceNotice(_ m: Msg) {
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

    // MARK: - 发送（★发送前 Emo.encode：4字节emoji转实体，与安卓 v5.47 同款修复）

    private func sendText() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        input = ""
        showEmojiPanel = false
        var f = baseParams()
        f["text"] = Emo.encode(t)
        f["type"] = "1"
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

    // MARK: - 红包（安卓 v5.32 同流程：getPacket 预检 → 开 H5 红包页 / 领取记录页）

    private func openPacket(_ packId: Int64) {
        Api.shared.post("/Home/Index/getPacket.html", form: ["id": String(packId)]) { pre in
            let canOpen = pre?.status == 1
            DispatchQueue.main.async {
                WebFallback.open(Api.host + (canOpen
                    ? "/Home/Index/getPacketPage.html?id=" + String(packId)
                    : "/Home/Index/getPacketLog.html?id=" + String(packId)), title: "微聊红包")
                refreshPacketStates()
            }
        }
    }

    private func openTransferDetail(_ packId: Int64) {
        WebFallback.open(Api.host + "/Home/Index/transferDetail.html?id=" + String(packId), title: "微聊转账")
    }

    // MARK: - 发红包（P3 出全屏原生页前先用弹窗，接口流程与安卓一致）

    private func redPacketDialog() {
        PayDialogs.redPacket(isGroup: isGroup) { amount, num, type, about in
            var f = baseParams()
            f["amount"] = String(format: "%.2f", amount)
            f["num"] = String(num)
            f["type"] = String(type)
            f["about"] = about
            postWithPayPwd("/Home/Index/createPacket.html", f) { _ in }
        }
    }

    // MARK: - 转账（P3 出全屏原生页前先用弹窗）

    private func transferEntry() {
        if !isGroup {
            transferDialog(qunId: 0, toId: chatId)
            return
        }
        Api.shared.post("/Api/Message/getQunUser.html", form: ["qunid": String(chatId)]) { r in
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

    // MARK: - 充值 / 提现（与安卓同接口）

    private func rechargeDialog() {
        Api.shared.post("/Api/Native/rechargeinfo.html", form: ["qunid": String(chatId)]) { r in
            DispatchQueue.main.async {
                guard let d = r?.data, d.int("has_admin") == 1, d.int("has_code") == 1 else {
                    PayDialogs.toast(r?.data?.str("info") ?? "暂无法充值")
                    return
                }
                PayDialogs.recharge(adminName: d.str("admin_name"), qrcode: d.str("qrcode")) { money in
                    Api.shared.post("/Home/Group/notifyRecharge.html",
                                    form: ["qunid": String(chatId), "money": String(format: "%.2f", money)]) { nr in
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
                                form: ["qunid": String(chatId), "money": String(format: "%.2f", money), "qrcode": url]) { r in
                    DispatchQueue.main.async { PayDialogs.toast(r?.msg ?? "网络异常") }
                }
            }
        }
    }

    // MARK: - 支付密码闸门（安卓 v5.47 同款：成功静默，失败提示）

    private func postWithPayPwd(_ path: String, _ form: [String: String], done: @escaping (JSONObject?) -> Void) {
        Api.shared.post(path, form: form) { r in
            if r?.status == 0, r?.raw["need_pwd"] as? Int == 1 {
                if r?.raw["pwd_set"] as? Int == 0 {
                    DispatchQueue.main.async { PayPwdSheet.shared.showSet = true }
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
            if r?.status != 1, let info = r?.msg, !info.isEmpty {
                DispatchQueue.main.async { PayDialogs.toast(info) }
            }
            done(r)
        }
    }

    // MARK: - 撤回

    private func recall(_ m: Msg) {
        guard Int64(Date().timeIntervalSince1970) - m.time <= 120 else {
            PayDialogs.toast("超过 2 分钟的消息不能撤回"); return
        }
        var f = baseParams()
        f["mid"] = String(m.mid)
        Api.shared.post(isGroup ? "/Api/Message/recall.html" : "/Api/Friendmessage/recall.html", form: f) { _ in }
    }
}

// MARK: - 气泡（1:1 H5 样式：红包 envelopes-back / 转账 zz-card / hb-fade 暖黄淡化）

struct Bubble: View {
    var m: Msg
    var mine: Bool
    var onTapImage: () -> Void
    var onTapHb: () -> Void
    var onTapZz: () -> Void
    var onRecall: () -> Void

    var body: some View {
        Group {
            if m.msgtype == "rc" {
                Text(mine ? "你撤回了一条消息" : "\(m.nickname) 撤回了一条消息")
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if mine { Spacer(minLength: 48) }
                    Avatar(url: m.avatar, fallback: m.nickname, size: 40).padding(.top, 4)
                    VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                        if !mine {
                            Text(m.nickname).font(.system(size: 11)).foregroundColor(Color(hex: 0x9B9B9B))
                        }
                        bubbleCore
                        Text(chatTime(m.time)).font(.system(size: 10)).foregroundColor(Color(hex: 0xB2B2B2))
                    }
                    if !mine { Spacer(minLength: 48) }
                }
            }
        }
    }

    @ViewBuilder private var bubbleCore: some View {
        if m.msgtype == "hb" {
            packetCard
        } else if m.msgtype == "zz" {
            transferCard
        } else if m.type == 2 {
            ChatImageBubble(path: m.text)
                .onTapGesture(perform: onTapImage)
                .contextMenu { if mine { Button("撤回", action: onRecall) } }
        } else if m.type == 3 {
            VoiceBubble(text: m.text, mine: mine)
        } else {
            EmoLabel(text: m.text, size: 15, color: .black)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(mine ? Color(hex: 0xA5E75A) : Color.white)
                .cornerRadius(8)
                .contextMenu { if mine { Button("撤回", action: onRecall) } }
        }
    }

    /// 红包卡（H5 .envelopes-back：#FB9F3C 信封行 + 白底条「微聊红包」；已领/领完 → hb-fade 暖黄）
    private var packetCard: some View {
        let faded = m.hbDone == 1 || m.hbMine == 1
        return Button(action: onTapHb) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image("b").resizable().scaledToFit()
                        .frame(height: 40).padding(.leading, 10)
                    VStack(alignment: .leading, spacing: 2) {
                        EmoLabel(text: m.text, size: 16,
                                 color: UIColor(Color(hex: faded ? 0xFFF3E2 : 0xFFFFFF)))
                        Text(m.hbDone == 1 ? "红包已领完" : (m.hbMine == 1 ? "已领取" : "领取红包"))
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: faded ? 0xFFF3E2 : 0xFFFFFF))
                    }
                    Spacer(minLength: 10)
                }
                .frame(height: 55)
                .frame(maxWidth: .infinity)
                .background(Color(hex: faded ? 0xF8C460 : 0xFB9F3C))
                Text("微聊红包")
                    .font(.system(size: 12)).foregroundColor(Color(hex: faded ? 0xC1854A : 0x333333))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .frame(height: 25)
                    .background(Color.white)
            }
            .frame(width: 210)
            .cornerRadius(5)
            .opacity(faded ? 0.93 : 1)
        }.buttonStyle(.plain)
    }

    /// 转账卡（H5 .zz-card：#FB9F3C + 白圆¥行 + 白底条「微聊转账」）
    private var transferCard: some View {
        Button(action: onTapZz) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("¥")
                        .font(.system(size: 19, weight: .medium)).foregroundColor(Color(hex: 0xFB9F3C))
                        .frame(width: 34, height: 34)
                        .background(Color.white).clipShape(Circle())
                        .padding(.leading, 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.zzAmount.isEmpty ? "转账" : m.zzAmount)
                            .font(.system(size: 16)).foregroundColor(.white)
                        Text(m.text.isEmpty ? "转账" : m.text)
                            .font(.system(size: 12)).foregroundColor(.white)
                    }
                    Spacer(minLength: 10)
                }
                .frame(height: 55)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xFB9F3C))
                Text("微聊转账")
                    .font(.system(size: 12)).foregroundColor(Color(hex: 0x666666))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .frame(height: 25)
                    .background(Color.white)
            }
            .frame(width: 210)
            .cornerRadius(5)
        }.buttonStyle(.plain)
    }

    private func chatTime(_ ts: Int64) -> String {
        guard ts > 0 else { return "" }
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        let now = Calendar.current
        if now.isDateInToday(d) { fmt.dateFormat = "HH:mm" }
        else if now.isDateInYesterday(d) { fmt.dateFormat = "'昨天' HH:mm" }
        else { fmt.dateFormat = "M月d日 HH:mm" }
        return fmt.string(from: d)
    }
}

// MARK: - 图片气泡（原始比例、宽度上限 150，安卓 v5.10 同观感）

struct ChatImageBubble: View {
    var path: String
    @State var img: UIImage?

    static var cache: [String: UIImage] = [:]

    var body: some View {
        Group {
            if let img = img {
                let w = min(150, max(40, img.size.width))
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: w, height: w * img.size.height / max(1, img.size.width))
                    .clipped().cornerRadius(8)
            } else {
                Color(.systemGray5).frame(width: 120, height: 120).cornerRadius(8)
            }
        }
        .onAppear {
            if let c = ChatImageBubble.cache[path] { img = c; return }
            Api.shared.fetchImage(path) { d in
                if let d = d, let i = UIImage(data: d) {
                    ChatImageBubble.cache[path] = i
                    DispatchQueue.main.async { img = i }
                }
            }
        }
    }
}

// MARK: - 语音气泡

struct VoiceBubble: View {
    var text: String
    var mine: Bool
    @State var player: AVAudioPlayer?

    var body: some View {
        Button(action: play) {
            Text("▶ 语音 \(dur)\"")
                .font(.system(size: 15)).foregroundColor(.black)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(mine ? Color(hex: 0xA5E75A) : Color.white)
                .cornerRadius(8)
        }.buttonStyle(.plain)
    }

    private var dur: Int {
        if let r = text.range(of: "|dur=") { return Int(text[r.upperBound...]) ?? 1 }
        return 1
    }

    private func play() {
        let path = text.components(separatedBy: "|dur=").first ?? text
        guard let url = URL(string: Api.host + path) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if let d = try? Data(contentsOf: url) {
            player = try? AVAudioPlayer(data: d)
            player?.play()
        }
    }
}

// MARK: - 成员面板 / 选人

struct MembersSheet: View {
    var isGroup: Bool
    var id: Int64
    var title: String
    @Environment(\.presentationMode) var mode
    @State var rows: [ChatScreen.MemberRow] = []
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
                        rows = (r?.arr ?? []).map { ChatScreen.MemberRow(id: $0.long("id"), nickname: $0.str("nickname"), money: $0.str("money")) }
                        total = r?.str("money_total") ?? ""
                    }
                }
            }
        }
    }
}

struct MemberPicker: View {
    var members: [ChatScreen.MemberRow]
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
