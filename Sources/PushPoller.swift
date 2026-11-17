import Foundation
import UserNotifications

/// 后台轮询：网页（WKWebView 的 WebContent 进程）一进后台就被系统挂起——11-17 实测
/// 切后台后 `/api/app/pushes` 一次请求都没有，页面里播静音音轨也没用。
/// 所以后台这段改成原生自己拉：只要 App 进程还活着（有那条静音音频撑着），
/// 主线程的 Timer 就还在转，拉到她的话就弹本地通知。
/// 回到前台立刻停掉，交还给网页（网页有自己的游标，不会重复显示）。
final class PushPoller {
    static let shared = PushPoller()

    private var timer: Timer?
    private var base: URL?
    private var busy = false
    private var ticks = 0
    private var seen: Double

    private init() {
        seen = UserDefaults.standard.double(forKey: "xj.pushSeen")
    }

    var running: Bool { timer != nil }

    func start(baseURL url: URL) {
        base = url
        // 第一次跑：游标从"现在"开始，别把历史上攒的几百条全当新消息弹出来
        if seen <= 0 {
            seen = Date().timeIntervalSince1970 * 1000
            UserDefaults.standard.set(seen, forKey: "xj.pushSeen")
        }
        guard timer == nil else { return }
        let ticker = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !busy, let base else { return }
        busy = true
        ticks += 1

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var query = components?.queryItems ?? []
        query.append(URLQueryItem(name: "since", value: String(Int(seen))))
        components?.queryItems = query
        guard let url = components?.url else { busy = false; return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            self.busy = false
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            var fresh: [[String: Any]] = []
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                fresh = items
            }

            var newest = self.seen
            for item in fresh {
                // JSON 里的整数会解成 NSNumber，直接 as? Double 不稳，走 doubleValue
                let at = (item["at"] as? NSNumber)?.doubleValue ?? 0
                guard at > self.seen else { continue }
                newest = max(newest, at)
                let text = (item["text"] as? String) ?? ""
                let body = text.isEmpty ? "她发了张图" : text
                DispatchQueue.main.async {
                    AlarmBridge.shared.notifyNow(title: "小鲸", body: body)
                }
            }
            if newest > self.seen {
                self.seen = newest
                UserDefaults.standard.set(newest, forKey: "xj.pushSeen")
            }

            // 每分钟报一次心跳：能证明「后台这些 Timer 到底有没有在跑」
            if self.ticks % 6 == 0 {
                Self.report(to: base, kind: "beat", extra: [
                    "ok": status == 200,
                    "status": status,
                    "ticks": self.ticks,
                    "fresh": fresh.count,
                    "keep": BackgroundKeeper.shared.isRunning,
                    "error": error?.localizedDescription ?? "",
                ])
            }
        }.resume()
    }

    /// 往服务端写一行诊断（App 启动探针 / 通知授权状态 / 后台心跳都走这里）
    static func report(to base: URL, kind: String, extra: [String: Any] = [:]) {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/api/app/diag"
        components?.queryItems = (components?.queryItems ?? []).filter { $0.name == "token" }
        guard let url = components?.url else { return }

        var payload = extra
        payload["kind"] = kind
        payload["at"] = Date().timeIntervalSince1970
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}
