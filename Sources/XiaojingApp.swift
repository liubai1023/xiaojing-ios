import SwiftUI

@main
struct XiaojingApp: App {
    @StateObject private var settings = Settings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}

/// 整个 App 就是一个全屏网页：左栏导航、聊天、朋友圈全在页面里，
/// 以后改界面只改电脑上的网页，不用重新打包。
struct RootView: View {
    @EnvironmentObject var settings: Settings
    @State private var showSetup = false
    @State private var reloadToken = UUID()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.05, green: 0.06, blue: 0.07).ignoresSafeArea()

            if settings.isConfigured {
                WebView(url: settings.url(for: "/"), reloadToken: reloadToken)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text("还没连上电脑").font(.headline)
                    Text("点右上角齿轮，填电脑地址和口令").font(.footnote).foregroundStyle(.secondary)
                    Button("现在设置") { showSetup = true }
                        .buttonStyle(.borderedProminent)
                }
            }

            Button {
                showSetup = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(9)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 6)
            .padding(.trailing, 10)
        }
        .onAppear { showSetup = !settings.isConfigured }
        .sheet(isPresented: $showSetup) {
            SetupView(isPresented: $showSetup, reloadToken: $reloadToken)
                .environmentObject(settings)
        }
    }
}
