import CoreLocation
import Foundation
import WebKit

/// 网页要位置时走这里：取一次坐标 → 反查中文地名 → 回给网页。
/// 网页侧入口是 window.webkit.messageHandlers.native.postMessage({type:"location"})，
/// 回调是 window.receiveNativeLocation({lat, lon, name}) 或 {error}。
final class LocationBridge: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var pending = false
    private var timeout: DispatchWorkItem?
    weak var webView: WKWebView?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        guard !pending else { return }
        pending = true
        armTimeout()
        switch manager.authorizationStatus {
        case .notDetermined:
            // 先要权限；用户在弹窗里点完会走 locationManagerDidChangeAuthorization
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(error: "定位权限没开，去设置里允许一次")
        default:
            manager.requestLocation()
        }
    }

    private func armTimeout() {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pending else { return }
            self.finish(error: "定位超时")
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pending else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(error: "定位权限没开，去设置里允许一次")
        default:
            break // 还没选完，继续等
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return finish(error: "没拿到坐标") }
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN")) { [weak self] places, _ in
            guard let self else { return }
            let place = places?.first
            var parts: [String] = []
            for piece in [place?.administrativeArea, place?.locality, place?.subLocality, place?.name] {
                if let piece, !piece.isEmpty, !parts.contains(piece) {
                    parts.append(piece)
                }
            }
            self.finish(payload: [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "name": parts.joined(),
            ])
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(error: error.localizedDescription)
    }

    private func finish(error: String) {
        finish(payload: ["error": error])
    }

    private func finish(payload: [String: Any]) {
        guard pending else { return }
        pending = false
        timeout?.cancel()
        timeout = nil
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.receiveNativeLocation && window.receiveNativeLocation(\(json));")
    }
}
