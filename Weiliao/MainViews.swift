import SwiftUI
import WebKit

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
            H5MainScreen(loggedIn: $loggedIn)
        } else {
            LoginView(loggedIn: $loggedIn)
        }
    }
}

// MARK: - 主界面 = H5 网页版主界面（登录后全屏打开，会话失效自动回原生登录页）

struct H5MainScreen: View {
    @Binding var loggedIn: Bool

    var body: some View {
        H5MainWeb(loggedIn: $loggedIn, url: Api.host + "/Home/Qun/index.html")
            .edgesIgnoringSafeArea(.bottom)   // 顶部留出状态栏/刘海区，页面头部不被挡
    }
}

struct H5MainWeb: UIViewRepresentable {
    @Binding var loggedIn: Bool
    var url: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // 注入 viewport 锁定（防页面过宽/横向晃动）
        let fix = """
        (function(){var m=document.querySelector('meta[name="viewport"]');if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);}m.setAttribute('content','width=device-width,initial-scale=1.0,maximum-scale=1.0,minimum-scale=1.0,user-scalable=no');var s=document.createElement('style');s.textContent='html,body{overflow-x:hidden!important;max-width:100vw!important;}';(document.head||document.documentElement).appendChild(s);})();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: fix, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // v1.7 追加：宽度自适应约束（iOS WKWebView 不完全遵守 CSS overflow-x:hidden，
        // 内容超宽时把 html/body 钳到可视宽度，从根上消灭横向可拖动的空间）
        let widthFix = """
        (function(){function fx(){var d=document.documentElement,b=document.body;if(!d||!b)return;var w=d.clientWidth;if(w>0&&(d.scrollWidth>w+1||b.scrollWidth>w+1)){d.style.width=w+'px';b.style.width=w+'px';d.style.overflowX='hidden';b.style.overflowX='hidden';}}setTimeout(fx,60);setTimeout(fx,600);setTimeout(fx,1800);window.addEventListener('resize',fx);})();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: widthFix, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        // 与安卓 WebView 观感对齐：禁横向回弹/晃动
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.backgroundColor = .white
        // KVO 兜底（v1.6）：监听 scrollView 的 contentOffset，横移立即归零
        wv.scrollView.addObserver(context.coordinator, forKeyPath: "contentOffset", options: [], context: nil)
        // v1.7 主锁：scrollView 代理钳制（拖动中每帧 + 拖动结束目标点都把 x 归零）
        let proxy = ScrollLockDelegate()
        proxy.orig = wv.scrollView.delegate
        wv.scrollView.delegate = proxy
        context.coordinator.lockDelegate = proxy
        context.coordinator.web = wv
        // 同步原生会话给 WebView（登录态带过去）
        if let cookies = HTTPCookieStorage.shared.cookies {
            for c in cookies { cfg.websiteDataStore.httpCookieStore.setCookie(c, completionHandler: {}) }
        }
        if let u = URL(string: url) { wv.load(URLRequest(url: u)) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.scrollView.delegate = nil
        uiView.scrollView.removeObserver(coordinator, forKeyPath: "contentOffset")
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: H5MainWeb
        var lockDelegate: ScrollLockDelegate?
        weak var web: WKWebView?
        init(_ p: H5MainWeb) { parent = p }
        // KVO 兜底：横向位移归零
        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "contentOffset", let sv = object as? UIScrollView, sv.contentOffset.x != 0 {
                sv.contentOffset.x = 0
            }
        }
        // WKWebView 导航后会把内部代理设回去 → commit/finish 时重新接管
        private func reassert(_ view: WKWebView) {
            if let cur = view.scrollView.delegate, cur !== lockDelegate { lockDelegate?.orig = cur }
            view.scrollView.delegate = lockDelegate
        }
        // 网页会话失效会 302 到登录页 → 切回原生登录页（与安卓 checkSession 行为一致）
        func webView(_ view: WKWebView, didCommit navigation: WKNavigation!) {
            reassert(view)
            if let u = view.url?.absoluteString, u.contains("User_login") {
                DispatchQueue.main.async { self.parent.loggedIn = false }
            }
        }
        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            reassert(view)
        }
    }
}

// MARK: - 登录（与安卓 LoginActivity 一比一：复刻网页版 MUI 风格）

struct LoginView: View {
    @Binding var loggedIn: Bool
    @State var phone = ""
    @State var pwd = ""
    @State var busy = false
    @State var err = ""
    @State var pwdVisible = false
    @State var showSignup = false

    // 与安卓同款色板（网页版主色 #45C01A）
    private let green = Color(hex: 0x45C01A)
    private let bgGray = Color(hex: 0xEFEFEF)
    private let barGray = Color(hex: 0xF7F7F7)
    private let hairline = Color(hex: 0xE5E5E5)

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏（MUI bar：浅灰底 + 居中标题）
            ZStack {
                barGray
                Text("登录").font(.system(size: 17)).foregroundColor(Color(hex: 0x262626))
            }.frame(height: 48)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // logo（网页版 Public/Home/member/imgs/log.png）
                    Image("Logo").resizable().scaledToFit()
                        .frame(height: 120)
                        .padding(.horizontal, 15).padding(.top, 10).padding(.bottom, 4)

                    // 页签：用户登录 | 用户注册（白底，激活绿下划线）
                    HStack(spacing: 0) {
                        tabCell("用户登录", active: true) {}
                        tabCell("用户注册", active: false) { showSignup = true }
                    }
                    .frame(height: 40)
                    .background(Color.white)
                    .padding(.horizontal, 30)

                    // 输入组（白卡 + 细分隔线，同 MUI input-group）
                    VStack(spacing: 0) {
                        TextField("请输入账号/手机号", text: $phone)
                            .keyboardType(.default)
                            .font(.system(size: 16))
                            .frame(height: 45).padding(.horizontal, 15)
                        Rectangle().fill(hairline).frame(height: 0.5)
                        HStack(spacing: 0) {
                            Group {
                                if pwdVisible {
                                    TextField("请输入密码", text: $pwd)
                                } else {
                                    SecureField("请输入密码", text: $pwd)
                                }
                            }
                            .font(.system(size: 16))
                            .frame(height: 45).padding(.leading, 15)
                            Button(pwdVisible ? "隐藏" : "显示") { pwdVisible.toggle() }
                                .font(.system(size: 13)).foregroundColor(green)
                                .padding(.leading, 8).padding(.trailing, 15)
                        }
                    }
                    .background(Color.white)
                    .padding(.horizontal, 15).padding(.top, 10)

                    if !err.isEmpty {
                        Text(err).font(.system(size: 13)).foregroundColor(.red).padding(.top, 8)
                    }

                    // 登录按钮（网页版 .submit：#45C01A 通栏绿块）
                    Button(action: login) {
                        Text(busy ? "登录中…" : "登录")
                            .font(.system(size: 16)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(green).cornerRadius(4)
                    }
                    .disabled(busy)
                    .padding(.horizontal, 15).padding(.top, 24)

                    // 注册按钮（网页版第二颗 .submit）
                    Button(action: { showSignup = true }) {
                        Text("注册")
                            .font(.system(size: 16)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(green).cornerRadius(4)
                    }
                    .padding(.horizontal, 15).padding(.top, 8)
                    Spacer().frame(height: 30)
                }
            }
        }
        .background(bgGray.ignoresSafeArea())
        // 注册 = 安卓 WebActivity standalone：全屏网页，页面自带头部
        .fullScreenCover(isPresented: $showSignup) {
            H5ChatScreen(url: Api.host + "/Home/Member/signup.html", title: "用户注册")
        }
    }

    private func tabCell(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label).font(.system(size: 14))
                    .foregroundColor(Color(hex: active ? 0x4C4C4C : 0x999999))
                Rectangle().fill(active ? green : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func login() {
        err = ""
        guard phone.count >= 5, pwd.count >= 4 else {
            err = "请输入账号和密码"
            return
        }
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
                if tab == 0 {
                    ConvList(convs: $convs)
                } else if tab == 2 {
                    WebViewHost(url: Api.host + "/Home/Faxian/index.html")
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    MePage(me: $me)
                }
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                tabBtn("微聊", 0)
                tabBtn("发现", 2)
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
                // 提现（平台）行已删除（2026-09-24 站长要求，与网页版/安卓同步）
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
