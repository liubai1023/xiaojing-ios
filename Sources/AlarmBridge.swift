import Foundation
import UserNotifications
import WebKit

/// 闹钟 / 到点提醒：网页把要排的时间交过来，这里用本地通知排上。
///
/// 苹果不允许第三方 App 改系统「时钟」里的闹钟，所以这是"App 自己的闹钟"：
/// 到点弹通知并响铃；静音或专注模式下可能只震动，不会像系统闹钟那样强行响。
///
/// 网页那边：
///   window.webkit.messageHandlers.native.postMessage({type:"alarm", id, at(秒), text, repeat})
///   window.webkit.messageHandlers.native.postMessage({type:"alarm-cancel", id})
final class AlarmBridge: NSObject, UNUserNotificationCenterDelegate {
    weak var webView: WKWebView?
    private var prepared = false

    /// 设成通知的 delegate，App 开着的时候也能弹横幅
    func prepare() {
        guard !prepared else { return }
        prepared = true
        UNUserNotificationCenter.current().delegate = self
    }

    func schedule(id: String, at: TimeInterval, text: String, repeatDaily: Bool) {
        prepare()
        guard at > 0 else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "小鲸"
            content.body = text
            content.sound = .default
            content.badge = 1

            let date = Date(timeIntervalSince1970: at)
            let calendar = Calendar.current
            let full = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger: UNNotificationTrigger
            if repeatDaily {
                let daily = DateComponents(hour: full.hour, minute: full.minute)
                trigger = UNCalendarNotificationTrigger(dateMatching: daily, repeats: true)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: full, repeats: false)
            }

            let identifier = "xj-alarm-\(id)"
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["xj-alarm-\(id)"])
    }

    /// 提前要权限：等他真收到消息时再弹授权框，系统会在后台弹，体验很怪
    func requestPermission() {
        prepare()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 立刻弹一条（网页收到消息时调，App 在后台也能弹）
    func notifyNow(title: String, body: String) {
        prepare()
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title.isEmpty ? "小鲸" : title
            if !body.isEmpty { content.body = body }
            content.sound = .default
            content.badge = 1
            let request = UNNotificationRequest(identifier: "xj-msg-\(UUID().uuidString)", content: content, trigger: nil)
            center.add(request)
        }
    }

    /// App 在前台时也弹横幅 + 响一声
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
