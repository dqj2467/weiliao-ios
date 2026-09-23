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

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // 注入 viewport 锁定：页面宽度=设备宽、禁缩放、禁横向溢出（与安卓 WebView 观感一致）
        let fix = """
        (function(){var m=document.querySelector('meta[name="viewport"]');if(!m){m=document.createElement('meta');m.name='viewport';(document.head||document.documentElement).appendChild(m);}m.setAttribute('content','width=device-width,initial-scale=1.0,maximum-scale=1.0,minimum-scale=1.0,user-scalable=no');var s=document.createElement('style');s.textContent='html,body{overflow-x:hidden!important;max-width:100vw!important;}';(document.head||document.documentElement).appendChild(s);})();
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: fix, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        // 与安卓 WebView 观感对齐：禁掉横向回弹/晃动（页面稍宽时手按屏幕左右抖）
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        // 同步原生会话给 WebView
        if let cookies = HTTPCookieStorage.shared.cookies {
            for c in cookies { cfg.websiteDataStore.httpCookieStore.setCookie(c, completionHandler: {}) }
        }
        if let u = URL(string: url) { wv.load(URLRequest(url: u)) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
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
