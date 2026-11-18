import Foundation

/// 连接配置：电脑地址 + 口令，存在 UserDefaults 里。
@MainActor
final class Settings: ObservableObject {
    @Published private(set) var host: String
    @Published private(set) var token: String

    private let hostKey = "xiaojing.host"
    private let tokenKey = "xiaojing.token"

    /// 两个固定入口：家里局域网 / 出门 Tailscale。连不上时互相兜底用。
    static let lanHost = "http://192.168.1.107:7788"
    static let tailscaleHost = "http://100.84.225.64:7788"

    init() {
        host = UserDefaults.standard.string(forKey: hostKey) ?? ""
        token = UserDefaults.standard.string(forKey: tokenKey) ?? ""
    }

    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save(host newHost: String, token newToken: String) {
        var trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.lowercased().hasPrefix("http") {
            trimmed = "http://" + trimmed
        }
        host = trimmed
        token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(host, forKey: hostKey)
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    func url(for path: String) -> URL {
        let base = host.hasSuffix("/") ? String(host.dropLast()) : host
        var components = URLComponents(string: base + path) ?? URLComponents(string: "http://127.0.0.1" + path)!
        if !token.isEmpty {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return components.url ?? URL(string: "http://127.0.0.1")!
    }
}
