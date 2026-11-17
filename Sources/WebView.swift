import SwiftUI
import WebKit

/// 全屏网页容器 + 与网页通信（网页点「＋」时开相册/相机，选完把图回传给网页）
struct WebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID
    @Binding var bridge: WebBridge?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let handler = WebBridge()
        config.userContentController.add(handler, name: "native")
        DispatchQueue.main.async { bridge = handler }

        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.keyboardDismissMode = .interactive
        web.scrollView.bounces = true
        web.allowsBackForwardNavigationGestures = false
        web.isOpaque = false
        let bg = UIColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 1)
        web.backgroundColor = bg
        web.scrollView.backgroundColor = bg
        // 别让系统自动加内边距，键盘弹起时页面自己撑满，避免中间露一块黑
        web.scrollView.contentInsetAdjustmentBehavior = .never

        handler.webView = web
        handler.locator.webView = web
        handler.alarms.prepare()
        handler.alarms.requestPermission()
        // 录音权限要靠 uiDelegate 放行，否则网页里 getUserMedia 直接失败
        web.uiDelegate = handler
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let stamp = "\(url.absoluteString)#\(reloadToken.uuidString)"
        if context.coordinator.lastStamp != stamp {
            context.coordinator.lastStamp = stamp
            web.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastStamp = ""
    }
}

struct SetupView: View {
    @EnvironmentObject var settings: Settings
    @Binding var isPresented: Bool
    @Binding var reloadToken: UUID
    @State private var host: String = ""
    @State private var token: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("电脑地址") {
                    TextField("192.168.1.107:7788", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("同一 WiFi 填电脑局域网 IP；出门用 Tailscale 就填 xxx.ts.net")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("口令") {
                    SecureField("口令", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("就是网页地址里 token= 后面那串")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("重新加载页面") {
                        reloadToken = UUID()
                        isPresented = false
                    }
                }
            }
            .navigationTitle("连接小鲸")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        settings.save(host: host, token: token)
                        reloadToken = UUID()
                        isPresented = false
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                host = settings.host
                token = settings.token
            }
        }
    }
}
