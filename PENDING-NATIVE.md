# 需要重编 ipa 才能生效的改动（攒着一起编）

> 这份清单里的代码都已经推到 `liubai1023/xiaojing-ios`，只是**手机上跑的还是旧包**。
> 等云 Mac 空出来，按「编译三步」走一遍就全部生效。

## 1. 后台通知（2026-11-18 改，最优先）

**问题**：手机切后台后收不到她的消息弹窗，点开 App 才看到。

**根因**
- 后台通知靠两条腿：`静音音频保活`（不让进程被挂起）+ `原生轮询`（PushPoller 每 10 秒拉一次）。
- 之前只在 `BackgroundKeeper.enabled` 为真时才开保活；用户关过一次，之后就永远收不到。
- 另外通知标题写死成「小鲸」，阿蓝发的也显示小鲸。

**改动**
- `XiaojingApp.swift`：`.background` 分支**无条件** `BackgroundKeeper.shared.start()`（注释写清了为什么）。
- `PushPoller.swift`：标题按 `item.source` 显示 `阿蓝` / `小鲸`。

**验收**：切到后台 → 让小鲸发一条 → 应该 10 秒内弹通知，标题是她的名字。

## 2. 鲸伴页的相机（2026-11-17 起一直没通）

**问题**：鲸伴页点快门没反应（主聊天页的相机是好的）。

**现状**
- 网页侧已经改成 `window.webkit.messageHandlers.native.postMessage({type:"camera"})`，
  并定义了 `window.receiveNativeImage` 接收照片。
- 原生侧 `XiaojingApp.swift` 的 `case "camera"` 已经有，但**没验证过鲸伴页能不能拿到这个桥**。
- 已埋诊断：点快门时会上报 `kind:"whale-camera", hasBridge:true/false` 到 `data/app-diag.log`。

**如果重编时想一并解决**：在 `WebBridge` 里确认 `userContentController` 是挂在**同一个 WKUserContentController** 上（iframe 里也能拿到），
必要时给鲸伴页加一条独立的 JS 注入。

## 3. 通知点击要进对应的会话（没做，属于新需求）

现在点通知只是打开 App，进的是上次停留的页面。
要做成「点阿蓝的通知 → 直接进阿蓝会话」，需要在 `AlarmBridge.notifyNow` 里带 `userInfo`，并在 App 启动时读 `open` 参数。

## 编译三步（照抄）

```bash
cd ~ ; rm -rf xiaojing-ios xiaojing-ios-main x.zip ; curl -L -o x.zip "https://codeload.github.com/liubai1023/xiaojing-ios/zip/refs/heads/main?x=$(date +%s)" ; unzip -qo x.zip ; mv xiaojing-ios-main xiaojing-ios ; cd xiaojing-ios ; ~/xcodegen/bin/xcodegen generate ; xcodebuild -project Xiaojing.xcodeproj -scheme Xiaojing -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | tail -4
```

```bash
cd ~ ; rm -rf ipa Xiaojing.ipa ; mkdir -p ipa/Payload ; cp -R ~/Library/Developer/Xcode/DerivedData/Xiaojing-*/Build/Products/Release-iphoneos/Xiaojing.app ipa/Payload/ ; cd ipa ; zip -qry ../Xiaojing.ipa Payload ; ls -lh ../Xiaojing.ipa
```

```bash
curl -s -X POST -H "Authorization: Bearer $(cat ~/t)" -H "Content-Type: application/json" -d '{"tag_name":"ipaN","name":"ipaN"}' https://api.github.com/repos/liubai1023/xiaojing-ios/releases -o ~/relN.json ; curl -s -X POST -H "Authorization: Bearer $(cat ~/t)" -H "Content-Type: application/octet-stream" --data-binary @$HOME/Xiaojing.ipa "$(grep -o '"upload_url": *"[^"]*' ~/relN.json | cut -d'"' -f4 | cut -d'{' -f1)?name=Xiaojing.ipa" -o ~/assetN.json ; grep -o '"browser_download_url": *"[^"]*' ~/assetN.json | cut -d'"' -f4
```

（`~/t` 里是 GitHub token；没有就先把 token 写进去。）
