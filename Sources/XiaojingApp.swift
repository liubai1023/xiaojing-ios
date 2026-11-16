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
                    .onAppear {
                        bridge?.onPickPhoto = { showPicker = true }
                        bridge?.onTakePhoto = { showCamera = true }
                    }
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
        .onChange(of: picked) { _, item in
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
            bridge?.sendImage("data:image/jpeg;base64,\(base64)")
        }
    }
}

/// 与网页通信：网页点「＋」通知我们开相册/相机；我们回传图片。
final class WebBridge: NSObject, WKScriptMessageHandler {
    var onPickPhoto: (() -> Void)?
    var onTakePhoto: (() -> Void)?
    weak var webView: WKWebView?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "pick": onPickPhoto?()
        case "camera": onTakePhoto?()
        default: break
        }
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
