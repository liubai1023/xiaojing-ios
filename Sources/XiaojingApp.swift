import SwiftUI

@main
struct XiaojingApp: App {
    @StateObject private var settings = Settings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: Settings
    @State private var showSetup = false

    var body: some View {
        TabView {
            WebTab(path: "/chat", title: "聊天", symbol: "bubble.left.and.bubble.right.fill")
            WebTab(path: "/feed", title: "动态", symbol: "book.closed.fill")
            WebTab(path: "/room", title: "我们", symbol: "person.3.fill")
        }
        .onAppear {
            showSetup = !settings.isConfigured
        }
        .sheet(isPresented: $showSetup) {
            SetupView(isPresented: $showSetup)
                .environmentObject(settings)
        }
    }
}

struct WebTab: View {
    @EnvironmentObject var settings: Settings
    let path: String
    let title: String
    let symbol: String

    var body: some View {
        NavigationStack {
            Group {
                if settings.isConfigured {
                    WebView(url: settings.url(for: path))
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                        Text("还没连上电脑")
                            .font(.headline)
                        Text("点右上角的齿轮，填电脑地址和口令")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tabItem { Label(title, systemImage: symbol) }
    }
}
