import SwiftUI
import WebKit

/// 一个带 Cookie 与自适应高度的 WKWebView：页面自己负责聊天列表和输入框。
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = false
        web.scrollView.keyboardDismissMode = .interactive
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if web.url != url {
            web.load(URLRequest(url: url))
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var settings: Settings
    @Binding var isPresented: Bool
    @State private var host: String = ""
    @State private var token: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("电脑地址") {
                    TextField("192.168.1.10:7788", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("同一 WiFi 就填电脑的局域网 IP；出门用 Tailscale 就填 xxx.ts.net")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("口令") {
                    SecureField("口令", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("连接小鲸")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        settings.save(host: host, token: token)
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
