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
    private var observing = false

    /// 来电/闹钟/别的 App 抢了音频之后，结束时要自己恢复，
    /// 不然保活就断了（直到用户再切回 App）。
    private func observeInterruptions() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                if options.contains(.shouldResume), self.running {
                    self.player?.play()
                }
            }
        }
    }

    func start() {
        guard !running else { return }
        observeInterruptions()
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers：不打断别人正在放的音乐/视频，两边混着走
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

        // 插标记，5 秒后确认：「保活开起来之后 App 还活着」
        UserDefaults.standard.set("starting", forKey: Self.guardKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard self?.running == true else { return }
            UserDefaults.standard.set("ok", forKey: Self.guardKey)
        }
    }

    func stop() {
        guard running else { return }
        player?.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// 给诊断用：现在到底在不在放
    var isRunning: Bool { running }

    // MARK: - 开关（App 里可以关掉，省电）

    private let enabledKey = "xj.keepalive"
    /// 上次「准备保活」插的标记：5 秒后还活着才算确认，没确认就等下次启动自动关掉
    private static let guardKey = "xj.keepalive.guard"

    var enabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 后台音频是免费账号下唯一能「不被挂起」的办法，但也最容易一开就崩（11-17 就这样崩过一次，
    /// 那时候连开屏都进不去）。所以开之前先插个标记，5 秒后自认活下来；
    /// 下次启动要是还看到「没确认」，就自动把开关关掉——宁可没通知，别让 App 打不开。
    static func recoverIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: guardKey) == "starting" else { return }
        defaults.set(false, forKey: "xj.keepalive")
        defaults.removeObject(forKey: guardKey)
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        if !on { stop() }
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
