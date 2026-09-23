import SwiftUI
import WebKit
import AVFoundation

// MARK: - 路由（网页兜底 / 支付密码弹窗 全局单例）

final class WebFallback: ObservableObject {
    static let shared = WebFallback()
    static var logoutFlag = false
    @Published var item: WebItem?
    static func open(_ u: String, title: String) {
        DispatchQueue.main.async {
            shared.item = WebItem(url: u, title: title)
        }
    }
}

struct WebItem: Identifiable {
    var url: String
    var title: String
    var id: String { url }
}

final class PayPwdSheet: ObservableObject {
    static let shared = PayPwdSheet()
    @Published var showSet = false
    @Published var showAsk = false
    var onPwd: ((String) -> Void)?
}

// MARK: - 根容器：挂载全局弹层

struct RootContainer: View {
    @ObservedObject var router = WebFallback.shared
    @ObservedObject var pwd = PayPwdSheet.shared

    var body: some View {
        RootView()
            .sheet(item: $router.item) { item in
                WebViewScreen(url: item.url, title: item.title)
            }
            .sheet(isPresented: $pwd.showSet) { PayPwdSetView() }
            .sheet(isPresented: $pwd.showAsk) { PayPwdAskView() }
    }
}

// MARK: - H5 聊天容器（与安卓 WebActivity 同方案：原生壳 + 全屏 H5 聊天页）

struct H5ChatScreen: View {
    var url: String
    var title: String
    @Environment(\.presentationMode) var mode

    var body: some View {
        ZStack(alignment: .topLeading) {
            WebViewHost(url: url)
            // 浮动返回（页面自带头部，这个只兜底用）
            Button(action: { mode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.22))
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .padding(.leading, 10)
            .padding(.top, 6)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - 网页兜底容器

struct WebViewScreen: View {
    var url: String
    var title: String
    @Environment(\.presentationMode) var mode

    var body: some View {
        NavigationView {
            WebViewHost(url: url)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(title)
                .navigationBarItems(leading: Button("‹ 返回") { mode.wrappedValue.dismiss() })
        }
    }
}

struct WebViewHost: UIViewRepresentable {
    var url: String

    func makeCoordinator() -> ScrollLockCoordinator { ScrollLockCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // 注入 viewport 锁定：页面宽度=设备宽、禁缩放、禁横向溢出（与安卓 WebView 观感一致）
        let fix = """
        (function(){var m=document.querySelector('meta[name="viewport"]');if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);}m.setAttribute('content','width=device-width,initial-scale=1.0,maximum-scale=1.0,minimum-scale=1.0,user-scalable=no');var s=document.createElement('style');s.textContent='html,body{overflow-x:hidden!important;max-width:100vw!important;}';(document.head||document.documentElement).appendChild(s);})();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: fix, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // v1.7 追加：宽度自适应约束。iOS 的 WKWebView 不完全遵守 CSS overflow-x:hidden
        // （安卓遵守，所以安卓端不晃、iOS 端仍能拖）——文档加载后若内容超宽，
        // 直接把 html/body 宽度钳到可视宽度并隐藏横向溢出，从根上消灭超宽 contentSize。
        let widthFix = """
        (function(){function fx(){var d=document.documentElement,b=document.body;if(!d||!b)return;var w=d.clientWidth;if(w>0&&(d.scrollWidth>w+1||b.scrollWidth>w+1)){d.style.width=w+'px';b.style.width=w+'px';d.style.overflowX='hidden';b.style.overflowX='hidden';}}setTimeout(fx,60);setTimeout(fx,600);setTimeout(fx,1800);window.addEventListener('resize',fx);})();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: widthFix, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        // 与安卓 WebView 观感对齐：禁掉横向回弹/晃动（页面稍宽时手按屏幕左右抖）
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.backgroundColor = .white
        // KVO 兜底（v1.6）：监听 scrollView 的 contentOffset，横移立即归零
        wv.scrollView.addObserver(context.coordinator, forKeyPath: "contentOffset", options: [], context: nil)
        // v1.7 主锁：scrollView 代理钳制。KVO 在手指拖动中会被手势逐帧覆盖（拖动仍会晃），
        // 代理锁在「每个滚动帧」和「拖动结束目标点」两处都把 x 归零，配合上方宽度约束才真正拖不动。
        let proxy = ScrollLockDelegate()
        proxy.orig = wv.scrollView.delegate
        wv.scrollView.delegate = proxy
        context.coordinator.lockDelegate = proxy
        context.coordinator.web = wv
        wv.navigationDelegate = context.coordinator
        // 同步原生会话给 WebView
        if let cookies = HTTPCookieStorage.shared.cookies {
            for c in cookies { cfg.websiteDataStore.httpCookieStore.setCookie(c, completionHandler: {}) }
        }
        if let u = URL(string: url) { wv.load(URLRequest(url: u)) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ScrollLockCoordinator) {
        uiView.scrollView.delegate = nil
        uiView.scrollView.removeObserver(coordinator, forKeyPath: "contentOffset")
    }
}

/// v1.7 横向锁（仅 iOS 端，不影响任何网页代码 / 安卓工程）：
/// scrollView 代理转发器——每个滚动帧钳 x=0，拖动目标点钳 x=0，其余全部转发给
/// WKWebView 自己的内部代理，滚动行为不受影响。
final class ScrollLockDelegate: NSObject, UIScrollViewDelegate {
    weak var orig: UIScrollViewDelegate?
    private func clamp(_ sv: UIScrollView) {
        if sv.contentOffset.x != 0 { sv.contentOffset.x = 0 }
    }
    func scrollViewDidScroll(_ sv: UIScrollView) {
        clamp(sv)
        orig?.scrollViewDidScroll?(sv)
    }
    func scrollViewWillBeginDragging(_ sv: UIScrollView) {
        orig?.scrollViewWillBeginDragging?(sv)
    }
    func scrollViewWillEndDragging(_ sv: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee.x = 0
        orig?.scrollViewWillEndDragging?(sv, withVelocity: velocity, targetContentOffset: targetContentOffset)
    }
    func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate decelerate: Bool) {
        orig?.scrollViewDidEndDragging?(sv, willDecelerate: decelerate)
    }
    func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
        orig?.scrollViewDidEndDecelerating?(sv)
    }
    func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
        orig?.scrollViewDidEndScrollingAnimation?(sv)
    }
    func scrollViewDidScrollToTop(_ sv: UIScrollView) {
        orig?.scrollViewDidScrollToTop?(sv)
    }
    // WKWebView 内部代理实现了这些方法 → 用消息转发兜底，避免内部行为丢失
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (orig?.responds(to: aSelector) ?? false)
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        (orig?.responds(to: aSelector) ?? false) ? orig! : super.forwardingTarget(for: aSelector)
    }
}

/// KVO 兜底 + 导航回调（WKWebView 会在导航后把内部代理设回去 → 每次 commit 重新接管）
final class ScrollLockCoordinator: NSObject, WKNavigationDelegate {
    var lockDelegate: ScrollLockDelegate?
    weak var web: WKWebView?
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "contentOffset", let sv = object as? UIScrollView, sv.contentOffset.x != 0 {
            sv.contentOffset.x = 0
        }
    }
    func webView(_ view: WKWebView, didCommit navigation: WKNavigation!) {
        reassert(view)
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        reassert(view)
    }
    private func reassert(_ view: WKWebView) {
        if let cur = view.scrollView.delegate, cur !== lockDelegate { lockDelegate?.orig = cur }
        view.scrollView.delegate = lockDelegate
    }
}

// MARK: - 支付密码（六格）

struct PayPwdAskView: View {
    @Environment(\.presentationMode) var mode
    @State var digits: [String] = Array(repeating: "", count: 6)

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("请输入 6 位支付密码").font(.system(size: 15, weight: .semibold)).padding(.top, 24)
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        TextField("", text: $digits[i])
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 44, height: 50)
                            .background(Color(.systemGray6)).cornerRadius(6)
                            .onChange(of: digits[i]) { v in
                                if v.count > 1 { digits[i] = String(v.suffix(1)) }
                            }
                    }
                }
                Button(action: confirm) {
                    Text("确 定").frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color(hex: 0x1AAD19)).foregroundColor(.white).cornerRadius(8)
                }.padding(.horizontal, 18)
                Spacer()
            }
            .navigationTitle("支付密码").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func confirm() {
        let pwd = digits.joined()
        guard pwd.count == 6 else { return }
        mode.wrappedValue.dismiss()
        PayPwdSheet.shared.onPwd?(pwd)
        PayPwdSheet.shared.onPwd = nil
    }
}

struct PayPwdSetView: View {
    @Environment(\.presentationMode) var mode
    @State var old = ""
    @State var p1 = ""
    @State var p2 = ""
    @State var msg = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("6 位数字，用于发红包 / 转账确认")) {
                    SecureField("原支付密码（首次设置不用填）", text: $old)
                    SecureField("新的 6 位支付密码", text: $p1).keyboardType(.numberPad)
                    SecureField("再输一遍确认", text: $p2).keyboardType(.numberPad)
                }
                if !msg.isEmpty { Text(msg).foregroundColor(.red).font(.system(size: 13)) }
                Section {
                    Button("保 存") { save() }
                }
            }
            .navigationTitle("支付密码").navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("关闭") { mode.wrappedValue.dismiss() })
        }
    }

    private func save() {
        guard p1.count == 6 else { msg = "支付密码必须是 6 位数字"; return }
        guard p1 == p2 else { msg = "两次输入不一致"; return }
        Api.shared.post("/Home/Paypwd/save.html",
                        form: ["oldpwd": old, "pwd": p1, "pwd2": p2]) { r in
            DispatchQueue.main.async {
                msg = r?.msg ?? "网络异常"
                if r?.status == 1 { mode.wrappedValue.dismiss() }
            }
        }
    }
}

// MARK: - 全屏看图

struct ImageViewer: View {
    var url: String
    @Environment(\.presentationMode) var mode
    @State var data: Data?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let d = data, let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFit()
            }
        }
        .onTapGesture { mode.wrappedValue.dismiss() }
        .onAppear {
            Api.shared.fetchImage(url) { d in DispatchQueue.main.async { data = d } }
        }
    }
}

/// sheet 包装（全屏看图用）
struct SheetItem: Identifiable {
    var u: String
    var id: String { u }
}
