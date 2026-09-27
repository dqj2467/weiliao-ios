import SwiftUI

// MARK: - 钱包类全屏页（1:1 还原安卓 v5.23+ 的 H5 式页面：白头部 46 + 返回箭头 + 内容滚动区）
// 红包页红头变体（群）：#FF605E + 白箭头 + 右上「记录」（安卓 v5.35 同款）

struct WalletPageScaffold<Content: View>: View {
    var title: String
    var redHeader: Bool = false
    var trailing: (String, () -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.presentationMode) var mode

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                (redHeader ? Color(hex: 0xFF605E) : Color.white)
                HStack(spacing: 0) {
                    Button(action: { mode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(redHeader ? .white : Color(hex: 0x333333))
                            .frame(width: 40, height: 46)
                    }
                    Spacer()
                    if let t = trailing {
                        Button(action: t.1) {
                            Text(t.0).font(.system(size: 14))
                                .foregroundColor(redHeader ? .white : Color(hex: 0x333333))
                                .padding(.trailing, 14)
                        }
                    }
                }
                Text(title).font(.system(size: 17, weight: .bold))
                    .foregroundColor(redHeader ? .white : Color(hex: 0x262626))
            }
            .frame(height: 46)
            Rectangle().fill(Color(hex: 0xE5E5E5)).frame(height: 0.5).opacity(redHeader ? 0 : 1)

            ScrollView(showsIndicators: false) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: 0xF2F2F2).ignoresSafeArea())
    }
}

// MARK: - 发红包页（安卓 redPacketPage 1:1：H5 send_packett 同布局）

struct RedPacketPage: View {
    var isGroup: Bool
    var chatId: Int64
    var onSent: () -> Void
    @Environment(\.presentationMode) var mode
    @State var loaded = false
    @State var loadErr = ""
    @State var wallet: String = "--"
    @State var type = 0            // 0=拼手气（总金额） 1=普通（单个金额）
    @State var amount = ""
    @State var num = ""
    @State var about = ""
    @State var showHistory = false

    private var label: String { type == 0 ? (isGroup ? "总金额" : "红包金额") : "单个金额" }
    private var total: Double {
        let a = Double(amount) ?? 0
        return (isGroup && type == 1) ? a * max((Int(num) ?? 0), 0) : a
    }

    var body: some View {
        WalletPageScaffold(title: isGroup ? "" : "发红包", redHeader: isGroup,
                           trailing: isGroup ? ("记录", { showHistory = true }) : nil) {
            if !loaded {
                Text(loadErr.isEmpty ? "加载中…" : loadErr)
                    .font(.system(size: 14)).foregroundColor(Color(hex: 0x999999))
                    .frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                VStack(spacing: 0) {
                    // 可用余额行（灰条 #F5F5F5）
                    HStack(spacing: 0) {
                        Text("可用余额").font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        Spacer()
                        Text(wallet).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        Text("元").font(.system(size: 14)).foregroundColor(Color(hex: 0x999999)).padding(.leading, 6)
                    }
                    .padding(.horizontal, 13).frame(height: 40)
                    .background(Color(hex: 0xF5F5F5))

                    // 金额行（白条）
                    HStack(spacing: 0) {
                        if isGroup {
                            Text("拼").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 3).padding(.vertical, 2)
                                .background(Color(hex: 0xC39615))
                                .opacity(type == 0 ? 1 : 0)
                        }
                        Text(label).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333)).padding(.leading, isGroup ? 5 : 2)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        Text("元").font(.system(size: 14)).foregroundColor(Color(hex: 0x999999)).padding(.leading, 6)
                    }
                    .padding(.horizontal, 13).frame(height: 40)
                    .background(Color.white)

                    // 切换提示（仅群聊）
                    if isGroup {
                        Button(action: { type = type == 0 ? 1 : 0 }) {
                            HStack(spacing: 4) {
                                Text(type == 0 ? "每抽到的金额随机," : "群里每人收到固定金额,")
                                    .font(.system(size: 13)).foregroundColor(Color(hex: 0x333333))
                                Text(type == 0 ? "改成普通红包" : "改成拼手气红包")
                                    .font(.system(size: 13)).foregroundColor(Color(hex: 0x3368AD))
                                Spacer()
                            }
                        }.frame(height: 40).padding(.horizontal, 13)
                    }

                    // 红包个数（白条，仅群聊）
                    if isGroup {
                        HStack(spacing: 0) {
                            Text("红包个数").font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                            TextField("填写个数", text: $num)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                            Text("个").font(.system(size: 14)).foregroundColor(Color(hex: 0x999999)).padding(.leading, 6)
                        }
                        .padding(.horizontal, 13).frame(height: 40)
                        .background(Color.white)
                    }

                    // 留言（白条）
                    HStack(spacing: 0) {
                        Text("留言").font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        TextField("恭喜发财，大吉大利", text: $about)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                    }
                    .padding(.horizontal, 13).frame(height: 40)
                    .background(Color.white)

                    // ￥合计
                    HStack(alignment: .top, spacing: 2) {
                        Text("￥").font(.system(size: 16)).foregroundColor(Color(hex: 0x333333))
                        Text(fmt2(total)).font(.system(size: 34, weight: .bold)).foregroundColor(Color(hex: 0x333333))
                    }.padding(.top, 24)

                    // 大按钮
                    Button(action: submit) {
                        Text("塞钱进红包").font(.system(size: 18)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(hex: isGroup ? 0xFF605E : 0xFFBA00))
                    }.padding(.top, 20)

                    if isGroup {
                        Text("未领取的红包，将于24小时发起退款")
                            .font(.system(size: 13)).foregroundColor(Color(hex: 0xA2A2A2))
                            .frame(maxWidth: .infinity).padding(.top, 18)
                    }
                    Spacer()
                }
            }
        }
        .fullScreenCover(isPresented: $showHistory) {
            WebViewScreen(url: Api.host + "/Home/Index/redpackhistory.html", title: "红包记录")
        }
        .onAppear { load() }
    }

    private func load() {
        var f: [String: String] = [:]
        if isGroup { f["qunid"] = String(chatId) } else { f["friendid"] = String(chatId) }
        Api.shared.post("/Api/Native/transferpage.html", form: f) { r in
            DispatchQueue.main.async {
                if let r = r, r.status == 200, let d = r.data {
                    wallet = d.str("wallet_money")
                    loaded = true
                } else {
                    loadErr = r.flatMap { $0.msg.isEmpty ? "加载失败" : $0.msg } ?? "网络异常"
                }
            }
        }
    }

    private func submit() {
        var a = Double(amount) ?? 0
        a = (a * 100).rounded() / 100
        guard a >= 0.01 else { PayDialogs.toast("请输入正确的金额"); return }
        var f: [String: String] = ["amount": fmt2(a), "type": String(type),
                                   "about": about.trimmingCharacters(in: .whitespaces), "pt_type": "1"]
        if isGroup {
            guard let n = Int(num), n >= 1 else { PayDialogs.toast("请填写红包个数"); return }
            f["num"] = String(n)
            f["qunid"] = String(chatId)
        } else {
            f["friendid"] = String(chatId)
        }
        PayPwdGate.post("/Home/Index/createPacket.html", params: f) { r in
            if let r = r, r.status == 1 {
                DispatchQueue.main.async {
                    mode.wrappedValue.dismiss()
                    onSent()
                }
            }
        }
    }
}

// MARK: - 转账页（安卓 transferPageDialog 1:1：金额大卡 + 收款方 + 群友网格 + 说明 + 服务费预览）

struct TransferPage: View {
    var isGroup: Bool
    var chatId: Int64
    var onSent: () -> Void
    @Environment(\.presentationMode) var mode
    @State var loaded = false
    @State var loadErr = ""
    @State var wallet: Double = 0
    @State var walletText = "--"
    @State var friendName = ""
    @State var friendFace = ""
    @State var members: [JSONObject] = []
    @State var selUid: Int64 = 0
    @State var selName = ""
    @State var selFace = ""
    @State var amount = ""
    @State var about = ""
    @State var feeNote = ""
    // 服务费参数（H5 zzFee 同口径）
    @State var feeOpen = 0
    @State var tMin: [Double] = []
    @State var tMax: [Double] = []
    @State var tFee: [Double] = []
    @State var bindMap: [Int64: Int64] = [:]
    @State var adminIds: [Int64] = []
    @State var confirmShow = false

    var body: some View {
        WalletPageScaffold(title: "转账") {
            if !loaded {
                Text(loadErr.isEmpty ? "加载中…" : loadErr)
                    .font(.system(size: 14)).foregroundColor(Color(hex: 0x999999))
                    .frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                VStack(spacing: 0) {
                    // 金额大卡
                    VStack(alignment: .leading, spacing: 0) {
                        Text("转账金额").font(.system(size: 13)).foregroundColor(Color(hex: 0x888888))
                        HStack(spacing: 8) {
                            Text("¥").font(.system(size: 30)).foregroundColor(Color(hex: 0x333333))
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 34)).foregroundColor(Color(hex: 0x333333))
                        }
                        Rectangle().fill(Color(hex: 0xE5E5E5)).frame(height: 1)
                        HStack(spacing: 0) {
                            Text("可用余额 ").font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                            Text("¥" + walletText).font(.system(size: 12)).foregroundColor(Color(hex: 0x333333))
                            Spacer()
                        }.padding(.vertical, 10)
                    }
                    .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 12)
                    .background(Color.white)

                    // 收款方行
                    HStack(spacing: 8) {
                        Text("收款方").font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        Spacer()
                        Text(isGroup ? (selName.isEmpty ? "请选择" : selName) : friendName)
                            .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        if !isGroup && !friendFace.isEmpty {
                            Avatar(url: friendFace, fallback: friendName, size: 34)
                        }
                    }
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Color.white).padding(.top, 10)

                    // 选择群友网格（4 列，头像 44，选中绿描边）
                    if isGroup && !members.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("选择群友").font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                            Text(selName.isEmpty ? "群聊转账需要先点选一位群友" : "已选择：" + selName)
                                .font(.system(size: 12)).foregroundColor(Color(hex: 0xFA9D3B))
                                .padding(.top, 6)
                            ScrollView(showsIndicators: false) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                                    ForEach(members, id: \.raw) { o in
                                        let uid = o.long("id")
                                        Button(action: { select(uid, o.str("nickname"), o.str("headimgurl")) }) {
                                            VStack(spacing: 4) {
                                                Avatar(url: o.str("headimgurl"), fallback: o.str("nickname"), size: 44)
                                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                                        .stroke(uid == selUid ? Color(hex: 0x07C160) : Color.clear, lineWidth: 2))
                                                Text(o.str("nickname"))
                                                    .font(.system(size: 11))
                                                    .foregroundColor(uid == selUid ? Color(hex: 0x07C160) : Color(hex: 0x666666))
                                                    .lineLimit(1)
                                            }
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.vertical, 8)
                            }
                            .frame(height: 232)
                        }
                        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 4)
                        .background(Color.white).padding(.top, 1)
                    }

                    // 转账说明
                    HStack(spacing: 0) {
                        Text("转账说明").font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        TextField("选填，最多 20 字", text: $about)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                    }
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Color.white).padding(.top, 1)

                    Button(action: trySubmit) {
                        Text("转账").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color(hex: 0x07C160)).cornerRadius(4)
                    }
                    .padding(.horizontal, 14).padding(.top, 26)

                    Text("转账实时到账，请确认收款方与金额无误")
                        .font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                        .frame(maxWidth: .infinity).padding(.top, 12)
                    if !feeNote.isEmpty {
                        Text(feeNote).font(.system(size: 12)).foregroundColor(Color(hex: 0xE6A23C))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 8)
                    }
                    Spacer().frame(height: 20)
                }
            }
        }
        .onAppear { load() }
        .onChange(of: amount) { _ in refreshFee() }
        .fullScreenCover(isPresented: $confirmShow) {
            ZZConfirmView(face: selFace, name: isGroup ? selName : friendName,
                          amount: amt, fee: curFee,
                          onOk: doTransfer)
        }
    }

    private var amt: Double { ((Double(amount) ?? 0) * 100).rounded() / 100 }
    private var curFee: Double { feeOf(amt, receiver: isGroup ? selUid : 0) }

    private func load() {
        var f: [String: String] = [:]
        if isGroup { f["qunid"] = String(chatId) } else { f["friendid"] = String(chatId) }
        Api.shared.post("/Api/Native/transferpage.html", form: f) { r in
            DispatchQueue.main.async {
                guard let r = r, r.status == 200, let d = r.data else {
                    loadErr = r.flatMap { $0.msg.isEmpty ? "加载失败" : $0.msg } ?? "网络异常"
                    return
                }
                walletText = d.str("wallet_money")
                wallet = Double(d.str("wallet_money")) ?? 0
                feeOpen = d.int("fee_open")
                tMin = Self.nums(d.str("fee_tier_min"))
                tMax = Self.nums(d.str("fee_tier_max"))
                tFee = Self.nums(d.str("fee_tier_fee"))
                for pr in d.str("fee_bind_map").split(separator: ",") {
                    let kv = pr.split(separator: ":")
                    if kv.count == 2, let k = Int64(kv[0].trimmingCharacters(in: .whitespaces)),
                       let v = Int64(kv[1].trimmingCharacters(in: .whitespaces)) { bindMap[k] = v }
                }
                for s in d.str("fee_admin_ids").split(separator: ",") {
                    if let v = Int64(s.trimmingCharacters(in: .whitespaces)), v > 0, !adminIds.contains(v) { adminIds.append(v) }
                }
                if let fr = d.dict("friend") {
                    friendName = fr.str("nickname").isEmpty ? "" : fr.str("nickname")
                    friendFace = fr.str("headimgurl")
                }
                members = d.arr
                loaded = true
            }
        }
    }

    private func select(_ uid: Int64, _ name: String, _ face: String) {
        selUid = uid; selName = name; selFace = face
        refreshFee()
    }

    private func refreshFee() {
        let a = Double(amount) ?? 0
        if a > wallet && wallet > 0 {
            amount = ""
            PayDialogs.toast("余额不足，可用余额 " + fmt2(wallet) + " 元")
        }
        let fee = feeOf(((a * 100).rounded() / 100), receiver: isGroup ? selUid : 0)
        if a > 0 && fee > 0 {
            var rule = ""
            for i in 0..<tFee.count where a + 0.0001 >= tMin[i] {
                rule = fmt2(tMin[i]) + (i < tMax.count && tMax[i] > 0 ? "~" + fmt2(tMax[i]) + " 元" : " 元以上")
            }
            feeNote = "本次平台服务费 ¥" + fmt2(fee) + "（" + rule + "），对方实收 ¥" + fmt2(a - fee)
        } else {
            feeNote = ""
        }
    }

    /// H5 zzFee 同口径：收款方未分配名下管理员/是管理员 → 不分润；起始金额≤金额的最大一档
    private func feeOf(_ amount: Double, receiver: Int64) -> Double {
        if feeOpen != 1 || amount <= 0 || tFee.isEmpty || receiver <= 0 { return 0 }
        guard let b = bindMap[receiver], b > 0 else { return 0 }
        if adminIds.contains(receiver) { return 0 }
        var hit = -1
        for i in 0..<tFee.count where amount + 0.0001 >= tMin[i] { hit = i }
        guard hit >= 0 else { return 0 }
        var fee = (tFee[hit] * 100).rounded() / 100
        if fee > amount - 0.01 { fee = ((amount - 0.01) * 100).rounded() / 100 }
        if fee < 0.01 { fee = 0 }
        return fee
    }

    private static func nums(_ csv: String) -> [Double] {
        csv.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func trySubmit() {
        let a = amt
        guard a > 0 else { PayDialogs.toast("请输入转账金额"); return }
        guard a >= 0.01 else { PayDialogs.toast("转账金额不能低于 0.01 元"); return }
        guard a <= wallet else { PayDialogs.toast("余额不足，请先充值"); return }
        if isGroup && selUid <= 0 { PayDialogs.toast("请先选择要转账的群友"); return }
        confirmShow = true
    }

    private func doTransfer() {
        var f: [String: String] = ["amount": fmt2(amt),
                                   "about": about.trimmingCharacters(in: .whitespaces)]
        if isGroup {
            f["qunid"] = String(chatId); f["toid"] = String(selUid)
        } else {
            f["friendid"] = String(chatId); f["toid"] = String(chatId)
        }
        PayPwdGate.post("/Home/Index/createTransfer.html", params: f) { r in
            if let r = r, r.status == 1 {
                DispatchQueue.main.async {
                    mode.wrappedValue.dismiss()
                    onSent()
                }
            }
        }
    }
}

// MARK: - 充值页（安卓 buildRechargeSheet 1:1）

struct RechargePage: View {
    var qunId: Int64
    @Environment(\.presentationMode) var mode
    @State var loaded = false
    @State var loadErr = ""
    @State var d: JSONObject?
    @State var money = ""
    @State var zoom = false

    var body: some View {
        WalletPageScaffold(title: "充值") {
            if !loaded {
                Text(loadErr.isEmpty ? "加载中…" : loadErr)
                    .font(.system(size: 14)).foregroundColor(Color(hex: 0x999999))
                    .frame(maxWidth: .infinity).padding(.top, 40)
            } else if let d = d {
                VStack(spacing: 12) {
                    // 顶部通知条
                    Text("ⓘ 向管理员转账充值后点击下方按钮，群里会自动发消息通知管理员核实。")
                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x9A6B1F))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xFFE3BA)))
                        .background(Color(hex: 0xFFF7EC))

                    if d.int("has_admin") == 0 || d.int("has_code") == 0 {
                        Text(d.str("info") + "\n可回到群聊直接发消息提醒管理员处理")
                            .font(.system(size: 14)).foregroundColor(Color(hex: 0xB0B0B0))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.vertical, 26)
                    } else {
                        // 管理员行
                        HStack(spacing: 10) {
                            Text("管").font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: 0xFFFF9D00))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color(hex: 0xFFF7EC)))
                                .overlay(Circle().stroke(Color(hex: 0xFFE3BA)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.str("admin_name")).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                                Text("我的名下管理员 · 充值收款码").font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                            }
                            Spacer()
                        }

                        // 二维码（点击放大）
                        Button(action: { zoom = true }) {
                            QrImg(url: d.str("qrcode"))
                                .frame(height: 240).frame(maxWidth: .infinity)
                                .background(Color.white.cornerRadius(10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
                        }.buttonStyle(.plain)

                        Text("点击二维码可全屏放大，方便截图/识别\n付款成功后点击下方按钮，群里自动通知管理员核实处理")
                            .font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                            .multilineTextAlignment(.center)

                        TextField("请输入付款金额（选填）", text: $money)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 15)).frame(height: 42).padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
                        Text("填写金额后，通知消息里会带上金额，方便管理员核对")
                            .font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: notify) {
                            Text("已付款，通知管理员处理").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color(hex: 0xFF9D00)).cornerRadius(23)
                        }.padding(.top, 6)
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
        .fullScreenCover(isPresented: $zoom) { ImageViewer(url: d?.str("qrcode") ?? "") }
        .onAppear { load() }
    }

    private func load() {
        Api.shared.post("/Api/Native/rechargeinfo.html", form: ["qunid": String(qunId)]) { r in
            DispatchQueue.main.async {
                if let r = r, r.status == 200 { d = r.data; loaded = true }
                else { loadErr = "加载失败" }
            }
        }
    }

    private func notify() {
        let m = Double(money) ?? 0
        Api.shared.post("/Home/Group/notifyRecharge.html",
                        form: ["qunid": String(qunId), "money": String(m)]) { r in
            DispatchQueue.main.async {
                PayDialogs.toast(r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常")
                if r?.status == 1 { mode.wrappedValue.dismiss() }
            }
        }
    }
}

struct QrImg: View {
    var url: String
    @State var img: UIImage?
    var body: some View {
        Group {
            if let img = img { Image(uiImage: img).resizable().scaledToFit() }
            else { Text("二维码加载中…").font(.system(size: 13)).foregroundColor(Color(hex: 0x999999)).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .onAppear {
            Api.shared.fetchImage(url) { d in
                if let d = d { DispatchQueue.main.async { img = UIImage(data: d) } }
            }
        }
    }
}

// MARK: - 提现页（安卓 buildWithdrawSheet 1:1）

struct WithdrawPage: View {
    var qunId: Int64
    @Environment(\.presentationMode) var mode
    @State var loaded = false
    @State var loadErr = ""
    @State var d: JSONObject?
    @State var money = ""
    @State var qrUrl = ""
    @State var qrImg: UIImage?
    @State var picking = false

    var body: some View {
        WalletPageScaffold(title: "提现") {
            if !loaded {
                Text(loadErr.isEmpty ? "加载中…" : loadErr)
                    .font(.system(size: 14)).foregroundColor(Color(hex: 0x999999))
                    .frame(maxWidth: .infinity).padding(.top, 40)
            } else if let d = d {
                VStack(spacing: 12) {
                    Text("ⓘ 提交申请会先冻结（扣除）余额，由管理员「" + d.str("bind_name") + "」打款到您的收款码；被拒绝会自动退回余额。")
                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x9A6B1F))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xFFE3BA)))
                        .background(Color(hex: 0xFFF7EC))

                    if d.int("bind_uid") <= 0 {
                        Text("你在该群还没有分配「名下管理员」\n请联系群管理员在「成员分配」里分配后，再来提现")
                            .font(.system(size: 14)).foregroundColor(Color(hex: 0xB0B0B0))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.vertical, 26)
                    } else if let pend = d.dict("pending") {
                        let t = pend.long("createtime") > 0
                            ? DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(pend.long("createtime"))), dateStyle: .short, timeStyle: .short) : ""
                        Text("您有一笔 " + pend.str("money") + " 元的提现申请正待管理员打款\n提交时间：" + t + "\n管理员处理前不能再提交新申请。")
                            .font(.system(size: 13)).foregroundColor(Color(hex: 0x9A6B1F))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xFFE3BA)))
                            .background(Color(hex: 0xFFF7EC))
                    } else {
                        // 卡1：可用余额 + 全部提现 + 金额
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 0) {
                                Text("可用余额（元）").font(.system(size: 13)).foregroundColor(Color(hex: 0x8A8A8A))
                                Spacer()
                                Button(action: { if qm > 0 { money = fmt2(qm) } }) {
                                    Text("全部提现").font(.system(size: 13)).foregroundColor(Color(hex: 0xE1251B))
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().stroke(Color(hex: 0xF3C1BD)))
                                }
                            }
                            Text("¥" + fmt2(qm)).font(.system(size: 24, weight: .bold)).foregroundColor(Color(hex: 0xE1251B))
                            TextField("请输入提现金额", text: $money)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 15)).frame(height: 42).padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
                        }
                        .padding(14).background(Color.white.cornerRadius(12))

                        // 卡2：我的收款码
                        VStack(alignment: .leading, spacing: 8) {
                            Text("我的收款码").font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: 0x333333))
                            HStack(alignment: .top, spacing: 12) {
                                if let qrImg = qrImg {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: qrImg).resizable().scaledToFill()
                                            .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xEEEEEE)))
                                        Button(action: { qrUrl = ""; qrImg = nil }) {
                                            Text("×").font(.system(size: 13)).foregroundColor(.white)
                                                .frame(width: 22, height: 22).background(Color.black.opacity(0.55))
                                        }
                                    }
                                } else {
                                    Button(action: { picking = true }) {
                                        VStack(spacing: 4) {
                                            Text("＋").font(.system(size: 26)).foregroundColor(Color(hex: 0xC9C9C9))
                                            Text("上传收款码").font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                                        }
                                        .frame(width: 96, height: 96)
                                        .background(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0D0D0)))
                                    }.buttonStyle(.plain)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("上传您的微信/支付宝收款二维码").font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                                    Text("管理员按这张码给您打款").font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                                    Text("jpg / png / gif，不超过 5MB").font(.system(size: 12)).foregroundColor(Color(hex: 0xB0B0B0))
                                }
                                Spacer()
                            }
                        }
                        .padding(14).background(Color.white.cornerRadius(12))

                        Button(action: submit) {
                            Text("提交申请").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color(hex: 0xE1251B)).cornerRadius(23)
                        }
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $picking) {
            ImagePicker { ui in
                guard let ui = ui, let data = ui.jpegData(compressionQuality: 0.85) else { return }
                uploadQr(data)
            }
        }
    }

    private var qm: Double { Double(d?.str("qun_money") ?? "") ?? 0 }

    private func load() {
        Api.shared.post("/Api/Native/withdrawpage.html", form: ["qunid": String(qunId)]) { r in
            DispatchQueue.main.async {
                guard let r = r, r.status == 200 else { loadErr = r.flatMap { $0.msg.isEmpty ? "加载失败" : $0.msg } ?? "网络异常"; return }
                d = r.data
                loaded = true
                qrUrl = d?.str("last_qr") ?? ""
                if !qrUrl.isEmpty {
                    Api.shared.fetchImage(qrUrl) { data in
                        if let data = data { DispatchQueue.main.async { qrImg = UIImage(data: data) } }
                    }
                }
            }
        }
    }

    private func uploadQr(_ data: Data) {
        Api.shared.upload("/Home/Index/fileUpload.html", fileData: data, fileName: "qrcode.jpg") { r in
            let path = r?.str("img_path") ?? ""
            DispatchQueue.main.async {
                if path.isEmpty { PayDialogs.toast("上传失败，请重试"); return }
                qrUrl = path
                qrImg = UIImage(data: data)
            }
        }
    }

    private func submit() {
        let m = Double(money) ?? 0
        guard m > 0 else { PayDialogs.toast("请输入正确的提现金额"); return }
        guard !qrUrl.isEmpty else { PayDialogs.toast("请先上传您的收款码"); return }
        Api.shared.post("/Home/Group/withdrawSubmit.html",
                        form: ["qunid": String(qunId), "money": String(m), "qrcode": qrUrl]) { r in
            DispatchQueue.main.async {
                PayDialogs.toast(r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常")
                if r?.status == 1 { mode.wrappedValue.dismiss() }
            }
        }
    }
}

// MARK: - 金额调整弹层（安卓 moneyAdjustDialog 1:1：＋加钱 / −扣钱）

struct MoneyAdjustSheet: View {
    var qunId: Int64
    var uid: Int64
    var nick: String
    var curMoney: String
    var onDone: () -> Void
    @Environment(\.presentationMode) var mode
    @State var money = ""
    @State var err = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(spacing: 12) {
                Text("金额调整").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                Text("「" + nick + "」当前群钱包余额：¥" + curMoney)
                    .font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                TextField("调整金额（元）", text: $money)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 15)).frame(height: 42).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
                if !err.isEmpty { Text(err).font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151)) }
                HStack(spacing: 12) {
                    Button(action: { go("plus") }) {
                        Text("＋ 加钱").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 44).background(Color(hex: 0x1AAD19)).cornerRadius(6)
                    }
                    Button(action: { go("minus") }) {
                        Text("− 扣钱").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 44).background(Color(hex: 0xFA5151)).cornerRadius(6)
                    }
                }
            }
            .padding(18).padding(.bottom, 8)
            .background(Color.white.cornerRadius(14))
            .padding(.horizontal, 30)
        }
    }

    private func go(_ act: String) {
        guard let m = Double(money), m > 0 else { err = "请输入正确的金额"; return }
        mode.wrappedValue.dismiss()
        Api.shared.post("/Home/Group/moneyAdjust.html",
                        form: ["qunid": String(qunId), "uid": String(uid), "act": act, "money": String(m)]) { r in
            DispatchQueue.main.async {
                PayDialogs.toast(r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常")
                if r?.status == 1 { onDone() }
            }
        }
    }
}

// MARK: - 添加群成员弹层（安卓 memberAddSheet 1:1）

struct MemberAddSheet: View {
    var qunId: Int64
    var onDone: () -> Void
    @Environment(\.presentationMode) var mode
    @State var kw = ""
    @State var tip = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text("添加群成员").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                TextField("输入对方微聊号", text: $kw)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 15)).frame(height: 42).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
                Text("微聊号 = 100 + 用户号（如 100900398）\n也可只输后 6 位用户号，或直接输昵称")
                    .font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                if !tip.isEmpty { Text(tip).font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151)) }
                Button(action: add) {
                    Text("添加").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 42).background(Color(hex: 0x1AAD19)).cornerRadius(6)
                }.padding(.top, 4)
            }
            .padding(18)
            .background(Color.white.cornerRadius(14))
            .padding(.horizontal, 30)
        }
    }

    private func add() {
        let k = kw.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { tip = "请输入微聊号"; return }
        tip = ""
        Api.shared.post("/Home/Group/addMember.html", form: ["qunid": String(qunId), "weihao": k]) { r in
            DispatchQueue.main.async {
                if r?.status == 1 {
                    let d = r?.data
                    PayDialogs.toast("已添加「" + (d?.str("nickname") ?? "") + "」")
                    mode.wrappedValue.dismiss()
                    onDone()
                } else {
                    tip = r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常"
                }
            }
        }
    }
}

// MARK: - 我在本群的昵称弹层（安卓 nickSheet 1:1）

struct NickSheet: View {
    var qunId: Int64
    var current: String
    var onDone: () -> Void
    @Environment(\.presentationMode) var mode
    @State var nick = ""
    @State var tip = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { mode.wrappedValue.dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text("我在本群的昵称").font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0x262626))
                TextField(current.isEmpty ? "留空恢复账号昵称" : current, text: $nick)
                    .font(.system(size: 15)).frame(height: 42).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
                if !tip.isEmpty { Text(tip).font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151)) }
                Button(action: save) {
                    Text("保存").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 42).background(Color(hex: 0x1AAD19)).cornerRadius(6)
                }
            }
            .padding(18)
            .background(Color.white.cornerRadius(14))
            .padding(.horizontal, 30)
        }
    }

    private func save() {
        Api.shared.post("/Home/Group/saveNickname.html",
                        form: ["qunid": String(qunId), "nickname": nick.trimmingCharacters(in: .whitespaces)]) { r in
            DispatchQueue.main.async {
                if r?.status == 1 { mode.wrappedValue.dismiss(); onDone() }
                else { tip = r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常" }
            }
        }
    }
}

// MARK: - 群公告弹层（只读查看）

struct NoticeSheet: View {
    var notice: String
    var body: some View {
        BottomSheetScaffold(title: "群公告") {
            Text(notice.isEmpty ? "暂无公告" : notice)
                .font(.system(size: 14)).foregroundColor(Color(hex: 0x333333))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}

// MARK: - 流水/时间文案（安卓 moneyLogStatus/listTime 同款）

func moneyLogStatus(_ s: Int) -> String {
    switch s {
    case 1: return "收入"; case 3: return "提现"; case 6: return "转账支出"
    case 7: return "转账收入"; case 8: return "分润收入"; case 9: return "群钱包调整"
    case 10: return "金额调整+"; case 11: return "金额调整-"; default: return "其他"
    }
}

func listTime(_ ts: Int64) -> String {
    guard ts > 0 else { return "" }
    let d = Date(timeIntervalSince1970: TimeInterval(ts))
    let f = DateFormatter()
    let cal = Calendar.current
    if cal.isDateInToday(d) { f.dateFormat = "HH:mm" }
    else if cal.isDateInYesterday(d) { f.dateFormat = "昨天 HH:mm" }
    else { f.dateFormat = "M月d日 HH:mm" }
    return f.string(from: d)
}

// MARK: - 群金额明细弹层（安卓 moneyLogDialog 1:1）

struct MoneyLogSheet: View {
    var qunId: Int64
    @State var rows: [JSONObject] = []
    @State var total = ""
    @State var err = ""

    var body: some View {
        BottomSheetScaffold(title: "群金额明细") {
            if !err.isEmpty {
                Text(err).font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                    .frame(maxWidth: .infinity).padding(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        let o = rows[i]
                        let acct = o.str("account").isEmpty ? "0.00" : o.str("account")
                        let neg = acct.hasPrefix("-")
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.str("nickname") + " #" + String(o.long("uid")))
                                    .font(.system(size: 14)).foregroundColor(Color(hex: 0x111111)).lineLimit(1)
                                Text(listTime(o.long("createtime")) + " · " + moneyLogStatus(o.int("status")))
                                    .font(.system(size: 11)).foregroundColor(Color(hex: 0xB2B2B2))
                            }
                            Spacer()
                            Text(acct).font(.system(size: 15, weight: .bold))
                                .foregroundColor(neg ? Color(hex: 0x353535) : Color(hex: 0xE64340))
                        }.padding(.horizontal, 14).padding(.vertical, 9)
                        Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 0.5)
                    }
                    if rows.isEmpty {
                        Text("暂无明细").font(.system(size: 13)).foregroundColor(Color(hex: 0xB2B2B2))
                            .frame(maxWidth: .infinity).padding(14)
                    }
                }
            }
        }
        .onAppear {
            Api.shared.post("/Api/Message/getQunMoneyLog.html", form: ["qunid": String(qunId)]) { r in
                DispatchQueue.main.async {
                    guard let r = r, r.status == 200 else {
                        err = r.flatMap { $0.msg.isEmpty ? "加载失败" : $0.msg } ?? "网络异常"
                        return
                    }
                    rows = r.arr
                    total = r.str("money_total")
                }
            }
        }
    }
}

// MARK: - 分润统计弹层（安卓 profitStatSheet 1:1：累计/今日/昨日/共N笔 + 最近50笔）

struct ProfitStatSheet: View {
    var qunId: Int64
    @State var rows: [JSONObject] = []
    @State var total = ""
    @State var today = ""
    @State var yesterday = ""
    @State var cnt = ""
    @State var err = ""

    var body: some View {
        BottomSheetScaffold(title: "分润统计") {
            if !err.isEmpty {
                Text(err).font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                    .frame(maxWidth: .infinity).padding(14)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("本群累计分润").font(.system(size: 14)).foregroundColor(Color(hex: 0x8A8A8A))
                        Spacer()
                        Text("¥" + total).font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: 0xFA9D3B))
                    }.padding(.horizontal, 14).padding(.bottom, 6)
                    Text("今日 ¥" + today + " · 昨日 ¥" + yesterday + " · 共 " + cnt + " 笔")
                        .font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.bottom, 6)
                    ForEach(rows.indices, id: \.self) { i in
                        let o = rows[i]
                        let fee = o.str("fee_desc")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.str("from_name") + " → " + o.str("to_name") + "（转 ¥" + o.str("amount") + "）")
                                .font(.system(size: 13)).foregroundColor(Color(hex: 0x262626)).lineLimit(1)
                            Text(o.str("time") + " · " + (fee.isEmpty ? "群内分润" : fee))
                                .font(.system(size: 11)).foregroundColor(Color(hex: 0xB2B2B2))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(hex: 0x1AAD19).opacity(Double(i) * 0))
                        .overlay(
                            HStack {
                                Spacer()
                                Text("+" + o.str("profit")).font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(hex: 0x1AAD19))
                            }.padding(.horizontal, 14)
                        )
                        Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 0.5)
                    }
                    if rows.isEmpty {
                        Text("本群还没有分润记录").font(.system(size: 13)).foregroundColor(Color(hex: 0xB2B2B2))
                            .frame(maxWidth: .infinity).padding(14)
                    }
                }
            }
        }
        .onAppear {
            Api.shared.post("/Api/Native/qunprofit.html", form: ["qunid": String(qunId)]) { r in
                DispatchQueue.main.async {
                    guard let r = r, r.status == 200, let d = r.data else {
                        err = r.flatMap { $0.msg.isEmpty ? "加载失败" : $0.msg } ?? "网络异常"
                        return
                    }
                    rows = d.listItems
                    total = d.str("total"); today = d.str("today")
                    yesterday = d.str("yesterday"); cnt = d.str("cnt")
                }
            }
        }
    }
}
