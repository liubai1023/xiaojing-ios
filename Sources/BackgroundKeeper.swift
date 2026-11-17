import AVFoundation
import Foundation

/// 让 App 在后台还能活着。
///
/// 没有付费开发者账号就没有 APNs，服务端推不过来；但 App 只要进程还活着，
/// 网页的轮询就能继续跑，收到消息时用本地通知弹出来。
/// iOS 允许"后台播音频"的应用不被挂起，所以这里循环一段无声的 wav。
///
/// 代价：耗一点电；App 里看不到任何声音（音量为 0）。
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()

    private var player: AVAudioPlayer?
    private var running = false

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        if player == nil {
            player = try? AVAudioPlayer(data: Self.silentWav())
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
        }
        player?.play()
        running = true
    }

    func stop() {
        guard running else { return }
        player?.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// 1 秒的静音 WAV：16bit 单声道 8kHz
    private static func silentWav() -> Data {
        let sampleRate = 8000
        let samples = sampleRate
        let dataSize = samples * 2
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        u32(16)
        u16(1)                       // PCM
        u16(1)                       // 单声道
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))  // 字节率
        u16(2)                       // block align
        u16(16)                      // 位深
        d.append(contentsOf: Array("data".utf8))
        u32(UInt32(dataSize))
        d.append(Data(repeating: 0, count: dataSize))
        return d
    }
}
