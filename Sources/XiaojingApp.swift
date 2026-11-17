import SwiftUI
import WebKit
import PhotosUI
import UIKit

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

struct RootView: View {
    @EnvironmentObject var settings: Settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSetup = false
    @State private var reloadToken = UUID()
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var picked: PhotosPickerItem?
    @State private var bridge: WebBridge?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(red: 0.05, green: 0.06, blue: 0.07).ignoresSafeArea()

            if settings.isConfigured {
                WebView(url: settings.url(for: "/"), reloadToken: reloadToken, bridge: $bridge)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                    Text("还没连上电脑").font(.headline)
                    Text("点右上角齿轮，填电脑地址和口令").font(.footnote).foregroundStyle(.secondary)
                    Button("现在设置") { showSetup = true }.buttonStyle(.borderedProminent)
                }
            }

            // 齿轮放右下角，避开顶栏的返回键
            Button { showSetup = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.bottom, 96)
            .padding(.trailing, 8)
        }
        .photosPicker(isPresented: $showPicker, selection: $picked, matching: .images)
        // iOS 16 只有单参数的 onChange；两参数版本是 iOS 17 的
        .onChange(of: picked) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await send(data)
                }
                picked = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                Task { await send(data) }
            }
            .ignoresSafeArea()
        }
        .onAppear { showSetup = !settings.isConfigured }
        .onReceive(NotificationCenter.default.publisher(for: .xjPickPhoto)) { _ in showPicker = true }
        .onReceive(NotificationCenter.default.publisher(for: .xjTakePhoto)) { _ in showCamera = true }
        .onChange(of: scenePhase) { phase in
            // 切到后台就开静音保活，网页才能继续轮询、才有后台通知（App 里可以关）
            if phase == .background {
                if BackgroundKeeper.shared.enabled { BackgroundKeeper.shared.start() }
            } else {
                BackgroundKeeper.shared.stop()
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView(isPresented: $showSetup, reloadToken: $reloadToken)
                .environmentObject(settings)
        }
    }

    /// 把图片压到 1280 以内，转 base64 交给网页，由网页显示并发给电脑
    private func send(_ data: Data) async {
        guard let image = UIImage(data: data) else { return }
        let side = max(image.size.width, image.size.height)
        let scale = min(1, 1280 / side)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = small.jpegData(compressionQuality: 0.82) else { return }
        let base64 = jpeg.base64EncodedString()
        await MainActor.run {
            let target = bridge ?? WebBridge.current
            target?.sendImage("data:image/jpeg;base64,\(base64)")
        }
    }
}

extension Notification.Name {
    static let xjPickPhoto = Notification.Name("xj.pickPhoto")
    static let xjTakePhoto = Notification.Name("xj.takePhoto")
}

/// 与网页通信：网页点「＋」通知我们开相册/相机；要位置时去取一次；要排闹钟时交给 AlarmBridge。
final class WebBridge: NSObject, WKScriptMessageHandler, WKUIDelegate {
    /// 当前这一个实例：SwiftUI 的 binding 是异步绑上的，选完图那一刻可能还是 nil
    static weak var current: WebBridge?
    var onPickPhoto: (() -> Void)?
    var onTakePhoto: (() -> Void)?
    let locator = LocationBridge()
    let alarms = AlarmBridge()
    weak var webView: WKWebView?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "pick":
            // 走通知而不是闭包：闭包是在 .onAppear 里赋的，那时 bridge 可能还没绑上
            NotificationCenter.default.post(name: .xjPickPhoto, object: nil)
        case "camera":
            NotificationCenter.default.post(name: .xjTakePhoto, object: nil)
        case "location": locator.request()
        case "alarm":
            guard let id = body["id"] as? String,
                  let text = body["text"] as? String,
                  let at = body["at"] as? Double else { return }
            let repeatDaily = (body["repeat"] as? String) == "daily"
            alarms.schedule(id: id, at: at, text: text, repeatDaily: repeatDaily)
        case "alarm-cancel":
            guard let id = body["id"] as? String else { return }
            alarms.cancel(id: id)
        case "notify":
            let title = (body["title"] as? String) ?? "小鲸"
            let text = (body["body"] as? String) ?? ""
            alarms.notifyNow(title: title, body: text)
        case "keepalive":
            BackgroundKeeper.shared.setEnabled((body["enabled"] as? Bool) ?? true)
        default: break
        }
    }

    /// 网页要录音（她说话的麦克风在网页里）时直接放行，系统权限由 Info.plist 里的说明负责
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func sendImage(_ dataURL: String) {
        guard let json = try? JSONSerialization.data(withJSONObject: [dataURL]),
              let text = String(data: json, encoding: .utf8) else { return }
        let js = "window.receiveNativeImage && window.receiveNativeImage(\(String(text.dropFirst().dropLast())));"
        webView?.evaluateJavaScript(js)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
