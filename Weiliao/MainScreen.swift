import SwiftUI

// MARK: - 原生主框架（1:1 移植安卓 MainActivity/TabBar/ContactsActivity：微聊/通讯录/发现/我 四 Tab）

struct Conv: Identifiable {
    var isGroup: Bool
    var id: Int64
    var title: String
    var ico: String
    var lastTime: Int64 = 0
    var unread: Int = 0
    var key: String { (isGroup ? "g" : "f") + String(id) }
    var cid: String { key }
}

struct ContactItem: Identifiable {
    var isHeader: Bool
    var isGroup: Bool
    var id: Int64
    var name: String
    var ico: String
    var key: String { (isGroup ? "g" : "f") + String(id) + (isHeader ? "h" : "") }
    var cid: String { key }
}

struct MainScreen: View {
    @Binding var loggedIn: Bool

    @State var tab = 0          // 0 微聊 1 通讯录 3 我（2 发现=直接开 H5）
    @State var convs: [Conv] = []
    @State var badge = 0
    @State var contacts: [ContactItem] = []
    @State var meInfo: JSONObject?

    @State var openChat: Conv? = nil
    @State var showLogoutConfirm = false
    @State var firstLoad = true

    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏（安卓 #EDEDED 52dp）
            ZStack {
                Color(hex: 0xEDEDED)
                Text(headerTitle).font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: 0x262626))
            }.frame(height: 48)

            Group {
                if tab == 0 { convList }
                else if tab == 1 { contactList }
                else { mePage }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Color.white)
        .onAppear { refreshAll() }
        .onReceive(timer) { _ in if tab == 0 { loadConvs(false) } }
        .fullScreenCover(item: $openChat) { c in
            ChatScreen(isGroup: c.isGroup, chatId: c.id, title: c.title,
                       onClosed: { loadConvs(true) })
        }
    }

    private var headerTitle: String {
        tab == 0 ? "微聊" : (tab == 1 ? "通讯录" : "我的")
    }

    // MARK: - Tab1 会话列表

    private var convList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(convs) { c in
                    Button(action: { openChat = c }) {
                        ConvRow(c: c)
                    }.buttonStyle(.plain)
                }
            }
        }
        .background(Color.white)
    }

    // MARK: - Tab2 通讯录（安卓 scope=contacts 口径）

    private var contactList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(contacts) { it in
                    if it.isHeader {
                        Text(it.name)
                            .font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15).padding(.vertical, 6)
                            .background(Color(hex: 0xF5F6F7))
                    } else {
                        Button(action: { openChat = Conv(isGroup: it.isGroup, id: it.id, title: it.name, ico: it.ico) }) {
                            HStack(spacing: 12) {
                                Avatar(url: it.ico, fallback: it.name, size: 42)
                                Text(it.name).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                                Spacer()
                                Text("›").font(.system(size: 18)).foregroundColor(Color(hex: 0xD9D9D9))
                            }
                            .padding(.horizontal, 15).padding(.vertical, 8)
                            .background(Color.white)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Tab4 我（与安卓 buildMePage 同构）

    private var mePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // ① 资料行
                HStack(spacing: 0) {
                    Avatar(url: meInfo?.str("headimgurl") ?? "", fallback: meInfo?.str("nickname") ?? "我", size: 60)
                        .padding(.trailing, 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meInfo?.str("nickname") ?? "…")
                            .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        Text("微聊号：" + weihaoText)
                            .font(.system(size: 12)).foregroundColor(Color(hex: 0xAAAAAA))
                    }
                    Spacer()
                    Image("ucqrcode").resizable().scaledToFit().frame(width: 25, height: 25).padding(.trailing, 8)
                    Text("›").font(.system(size: 18)).foregroundColor(Color(hex: 0xD9D9D9))
                }
                .padding(.horizontal, 15)
                .frame(height: 76).background(Color.white)

                // ② 钱包
                meRow(icon: "uc1", label: "钱包", right: {
                    Text("余额：" + (meInfo?.str("money") ?? "--") + "元")
                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x808080))
                }) {
                    WebFallback.open(Api.host + "/Home/Member/redpacklog.html", title: "钱包")
                }

                // ③ 明细
                meRow(icon: "uc2", label: "明细", right: { EmptyView() }) {
                    WebFallback.open(Api.host + "/Home/Member/redpacklog.html", title: "余额明细")
                }

                // ⑤ 支付密码
                meRow(icon: "uc4", label: "支付密码", right: {
                    Text(paypwdText)
                        .font(.system(size: 13)).foregroundColor(paypwdSet ? Color(hex: 0x808080) : Color(hex: 0xE64340))
                }) {
                    PayPwdSheet.shared.showSet = true
                }

                // ⑥ 设置（安卓同款：点击无动作）
                meRow(icon: "uc4", label: "设置", right: { EmptyView() }) { }

                // ⑦ 退出登录
                Button(action: {
                    PayDialogs.confirm("确定要退出登录吗？") { logout() }
                }) {
                    Text("退出登录").font(.system(size: 15)).foregroundColor(Color(hex: 0xE64340))
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Color.white)
                }.buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .background(Color(hex: 0xEFEFEF))
        .onAppear { loadMe() }
    }

    private func meRow<RT: View>(icon: String, label: String, @ViewBuilder right: () -> RT,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(icon).resizable().scaledToFit().frame(width: 25, height: 25).padding(.trailing, 14)
                Text(label).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                Spacer()
                right()
            }
            .padding(.horizontal, 15)
            .frame(height: 52).background(Color.white)
        }.buttonStyle(.plain)
    }

    private var weihaoText: String {
        let w = meInfo?.str("weihao") ?? ""
        return w.isEmpty ? String(meInfo?.long("id") ?? 0) : w
    }
    private var paypwdSet: Bool { meInfo?.int("paypwd_set") == 1 }
    private var paypwdText: String { paypwdSet ? "已设置" : "未设置" }

    // MARK: - 底部 TabBar（安卓 TabBar.build 同款：4 图标+文字+角标）

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabCell(0, icon: "icon_chat", iconOn: "icon_chat_HL", label: "微聊", showBadge: true)
            tabCell(1, icon: "icon_abook", iconOn: "icon_abook_HL", label: "通讯录", showBadge: false)
            tabCell(2, icon: "icon_explore", iconOn: "icon_explore_HL", label: "发现", showBadge: false)
            tabCell(3, icon: "icon_me", iconOn: "icon_me_HL", label: "我", showBadge: false)
        }
        .frame(height: 56)
        .background(Color(hex: 0xFAFAFA))
    }

    private func tabCell(_ idx: Int, icon: String, iconOn: String, label: String, showBadge: Bool) -> some View {
        Button(action: { tapTab(idx) }) {
            VStack(spacing: 2) {
                ZStack(alignment: .top) {
                    Image(tab == idx ? iconOn : icon).resizable().scaledToFit()
                        .frame(width: 25, height: 25)
                    if showBadge && badge > 0 {
                        Text(badge > 99 ? "99+" : String(badge))
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                            .background(Color(hex: 0xFA5151)).cornerRadius(9)
                            .offset(x: 10, y: -4)
                    }
                }
                Text(label).font(.system(size: 11))
                    .foregroundColor(tab == idx ? Color(hex: 0x45C01A) : Color(hex: 0x7F7F7F))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.buttonStyle(.plain)
    }

    private func tapTab(_ idx: Int) {
        if idx == 2 {   // 发现：H5 发现页（安卓 v5.13 同款）
            WebFallback.open(Api.host + "/Home/Faxian/index.html", title: "发现")
            return
        }
        tab = idx
        if idx == 1 { loadContacts() }
        if idx == 3 { loadMe() }
    }

    // MARK: - 数据

    private func refreshAll() {
        loadConvs(true)
        if tab == 1 { loadContacts() }
        if tab == 3 { loadMe() }
    }

    private func loadConvs(_ z: Bool) {
        let g = Api.shared
        g.post("/Api/Native/groups.html", form: [:]) { gr in
            var arr: [Conv] = []
            if gr?.status == 200 {
                for o in gr?.data?.listItems ?? [] {
                    arr.append(Conv(isGroup: true, id: o.long("id"), title: o.str("name"),
                                    ico: o.str("ico"), lastTime: o.long("last_time"), unread: o.int("unread")))
                }
            }
            g.post("/Api/Native/friends.html", form: [:]) { fr in
                if fr?.status == 200 {
                    for o in fr?.data?.listItems ?? [] {
                        arr.append(Conv(isGroup: false, id: o.long("id"), title: o.str("nickname"),
                                        ico: o.str("headimgurl"), lastTime: 0, unread: o.int("unread")))
                    }
                }
                arr.sort { a, b in
                    if a.unread != b.unread { return a.unread > b.unread }
                    return a.lastTime > b.lastTime
                }
                let total = arr.reduce(0) { $0 + $1.unread }
                DispatchQueue.main.async {
                    convs = arr
                    badge = total
                    if firstLoad && !arr.isEmpty { firstLoad = false }
                }
            }
        }
    }

    private func loadContacts() {
        Api.shared.post("/Api/Native/groups.html", form: ["scope": "contacts"]) { gr in
            var arr: [ContactItem] = []
            let gl = gr?.data?.listItems ?? []
            if !gl.isEmpty {
                arr.append(ContactItem(isHeader: true, isGroup: true, id: 0, name: "群聊", ico: ""))
                for o in gl {
                    arr.append(ContactItem(isHeader: false, isGroup: true, id: o.long("id"),
                                           name: o.str("name"), ico: o.str("ico")))
                }
            }
            Api.shared.post("/Api/Native/friends.html", form: [:]) { fr in
                let fl = fr?.data?.listItems ?? []
                if !fl.isEmpty {
                    arr.append(ContactItem(isHeader: true, isGroup: false, id: 0, name: "好友", ico: ""))
                    for o in fl {
                        arr.append(ContactItem(isHeader: false, isGroup: false, id: o.long("id"),
                                               name: o.str("nickname"), ico: o.str("headimgurl")))
                    }
                }
                DispatchQueue.main.async { contacts = arr }
            }
        }
    }

    private func loadMe() {
        Api.shared.post("/Api/Native/me.html", form: [:]) { r in
            guard r?.status == 200, let d = r?.data else { return }
            DispatchQueue.main.async { meInfo = d }
        }
    }

    private func logout() {
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        loggedIn = false
    }
}

// MARK: - 会话行（安卓 ConvAdapter 同构：头像48/标题16粗/时间12/红角标）

struct ConvRow: View {
    var c: Conv
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Avatar(url: c.ico, fallback: c.title, size: 48)
                if c.unread > 0 {
                    Text(c.unread > 99 ? "99+" : String(c.unread))
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18)
                        .background(Color(hex: 0xFA5249)).cornerRadius(9)
                        .offset(x: 6, y: -6)
                }
            }
            .padding(.leading, 14).padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.system(size: 16, weight: .semibold)).foregroundColor(Color(hex: 0x262626))
                if c.isGroup {
                    Text(c.unread > 0 ? "[新消息] 点开查看" : "群聊")
                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                }
            }
            Spacer()
            if c.lastTime > 0 {
                Text(listTime(c.lastTime))
                    .font(.system(size: 12)).foregroundColor(Color(hex: 0xB2B2B2))
                    .padding(.trailing, 14)
            }
        }
        .padding(.vertical, 10).background(Color.white)
    }

    private func listTime(_ ts: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter()
        let now = Calendar.current
        if now.isDateInToday(d) { f.dateFormat = "HH:mm" }
        else if now.isDateInYesterday(d) { f.dateFormat = "昨天" }
        else { f.dateFormat = "M月d日" }
        return f.string(from: d)
    }
}
