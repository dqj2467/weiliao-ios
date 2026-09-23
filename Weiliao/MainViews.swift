import SwiftUI

@main
struct WeiliaoApp: App {
    var body: some Scene {
        WindowGroup { RootContainer() }
    }
}

/// 入口：有会话直接进主界面，否则登录
struct RootView: View {
    @AppStorage("logged_in") var loggedIn = false
    var body: some View {
        if loggedIn {
            MainView()
        } else {
            LoginView(loggedIn: $loggedIn)
        }
    }
}

// MARK: - 登录

struct LoginView: View {
    @Binding var loggedIn: Bool
    @State var phone = ""
    @State var pwd = ""
    @State var busy = false
    @State var err = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 72)
            Text("微聊").font(.system(size: 34, weight: .bold)).foregroundColor(.green)
            Text("登录后和好友畅聊").font(.system(size: 14)).foregroundColor(.gray).padding(.top, 6)
            Spacer().frame(height: 36)
            TextField("手机号", text: $phone)
                .keyboardType(.phonePad)
                .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                .padding(.horizontal, 32)
            SecureField("密码", text: $pwd)
                .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                .padding(.horizontal, 32).padding(.top, 12)
            if !err.isEmpty {
                Text(err).font(.system(size: 13)).foregroundColor(.red).padding(.top, 8)
            }
            Button(action: login) {
                Text(busy ? "登录中…" : "登 录")
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color(hex: 0x1AAD19)).foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(busy)
            .padding(.horizontal, 32).padding(.top, 28)
            Button("没有账号？注册新用户") {
                WebFallback.open(Api.host + "/Home/Member/register.html", title: "注册")
            }
            .font(.system(size: 14)).foregroundColor(.blue).padding(.top, 24)
            Spacer()
        }
    }

    private func login() {
        err = ""
        busy = true
        Api.shared.post("/Home/Member/login.html",
                        form: ["phone": phone, "password": pwd]) { r in
            DispatchQueue.main.async {
                busy = false
                if let r = r, r.status == 1 {
                    loggedIn = true
                } else {
                    err = "手机号或密码错误"
                }
            }
        }
    }
}

// MARK: - 主界面（会话 / 我的）

struct ConvItem: Identifiable {
    var isGroup: Bool
    var id: Int64
    var title: String
    var ico: String
    var unread: Int
    var lastTime: Int64
    var key: String { (isGroup ? "g" : "f") + String(id) }
    var uid: Int64 { id }
}

struct MeInfo {
    var id: Int64 = 0
    var nickname = ""
    var money = "0.00"
    var avatar = ""
}

struct MainView: View {
    @State var tab = 0
    @State var convs: [ConvItem] = []
    @State var me = MeInfo()
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if tab == 0 { ConvList(convs: $convs) } else { MePage(me: $me) }
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                tabBtn("微聊", 0)
                tabBtn("我的", 1)
            }.frame(height: 52).background(Color(.systemGray6))
        }
        .onAppear { refreshAll() }
        .onReceive(timer) { _ in refreshConvs() }
    }

    private func tabBtn(_ label: String, _ i: Int) -> some View {
        Button(action: { tab = i; if i == 1 { loadMe() } }) {
            VStack(spacing: 2) {
                Text(label).font(.system(size: 12))
                    .foregroundColor(tab == i ? Color(hex: 0x1AAD19) : .gray)
            }.frame(maxWidth: .infinity)
        }
    }

    private func refreshAll() { refreshConvs(); loadMe() }

    private func loadMe() {
        Api.shared.post("/Api/Native/me.html", form: [:]) { r in
            DispatchQueue.main.async {
                if let d = r?.data {
                    me = MeInfo(id: d.long("id"), nickname: d.str("nickname"),
                                money: d.str("money"), avatar: d.str("headimgurl"))
                }
            }
        }
    }

    private func refreshConvs() {
        Api.shared.post("/Api/Native/groups.html", form: [:]) { g in
            Api.shared.post("/Api/Native/friends.html", form: [:]) { f in
                DispatchQueue.main.async {
                    var out: [ConvItem] = []
                    for o in g?.data?.list ?? [] {
                        out.append(ConvItem(isGroup: true, id: o.long("id"), title: o.str("name"),
                                            ico: o.str("ico"), unread: o.int("unread"),
                                            lastTime: o.long("last_time")))
                    }
                    for o in f?.data?.list ?? [] {
                        out.append(ConvItem(isGroup: false, id: o.long("id"), title: o.str("nickname"),
                                            ico: o.str("headimgurl"), unread: o.int("unread"), lastTime: 0))
                    }
                    out.sort { a, b in
                        if a.unread != b.unread { return a.unread > b.unread }
                        return a.lastTime > b.lastTime
                    }
                    convs = out
                }
            }
        }
    }
}

struct ConvList: View {
    @Binding var convs: [ConvItem]
    var body: some View {
        List(convs) { c in
            NavigationLink(destination: H5ChatScreen(
                url: c.isGroup
                    ? Api.host + "/Home/Index/index.html?id=\(c.id)&_lc=1"
                    : Api.host + "/Home/Index/friendmsn.html?friendid=\(c.id)",
                title: c.title)) {
                HStack {
                    Avatar(url: c.ico, fallback: c.title, size: 48)
                    Text(c.title).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if c.unread > 0 {
                        Text("\(c.unread)").font(.system(size: 11)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red).clipShape(Capsule())
                    }
                }
            }
        }.listStyle(.plain)
    }
}

struct MePage: View {
    @Binding var me: MeInfo
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Avatar(url: me.avatar, fallback: me.nickname, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(me.nickname).font(.system(size: 17, weight: .bold))
                        Text("余额 ¥\(me.money)").font(.system(size: 13)).foregroundColor(.orange)
                    }
                    Spacer()
                }
                .padding(16).background(Color.white).cornerRadius(14)
                .padding(.horizontal, 12)
                MeRow(label: "支付密码") { PayPwdSheet.shared.showSet = true }
                MeRow(label: "余额明细") { WebFallback.open(Api.host + "/Home/Index/redpacklog.html", title: "余额明细") }
                MeRow(label: "提现（平台）") { WebFallback.open(Api.host + "/Home/Tixian/index.html", title: "提现") }
                MeRow(label: "退出登录") {
                    for c in HTTPCookieStorage.shared.cookies ?? [] { HTTPCookieStorage.shared.deleteCookie(c) }
                    WebFallback.logoutFlag = true
                }
            }.padding(.top, 12)
        }
    }
}

struct MeRow: View {
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundColor(.black)
                Spacer()
                Text("›").foregroundColor(.gray)
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(Color.white).cornerRadius(14)
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - 通用小组件

struct Avatar: View {
    var url: String
    var fallback: String
    var size: CGFloat
    @State var img: UIImage?
    var body: some View {
        Group {
            if let img = img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(.systemGray4)
                    Text(String(fallback.prefix(1))).foregroundColor(.white).font(.system(size: size * 0.35, weight: .bold))
                }
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            guard !url.isEmpty else { return }
            Api.shared.fetchImage(url) { d in
                if let d = d, let i = UIImage(data: d) { DispatchQueue.main.async { img = i } }
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
