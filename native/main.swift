import Cocoa
import WebKit
import ServiceManagement

// Claude 使用履歴ダッシュボード（メニューバー常駐アプリ）
// メニューバーに今日のトークン数を表示し、クリックで詳細メニュー、
// 「ダッシュボードを開く」で専用ウィンドウ（WKWebView）を表示する。10 分ごとに自動集計する。

let info = Bundle.main.infoDictionary ?? [:]
let dashboardDir = info["DashboardDir"] as? String ?? ""
let pythonPath = info["PythonPath"] as? String ?? "/usr/bin/python3"
let dashboardURL = URL(fileURLWithPath: dashboardDir)
let htmlURL = dashboardURL.appendingPathComponent("claude-usage-dashboard.html")
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/claude-usage-dashboard.log")

struct DayStat {
    let day: String
    let tokens: Int
    let responses: Int
}

/// 表示できる期間。days が 0 のときは全期間
let periods: [(days: Int, name: String)] = [
    (1, "今日"), (7, "直近7日間"), (30, "直近30日間"), (0, "全期間"),
]

func tok(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1e9 { return String(format: "%.2fB", v / 1e9) }
    if v >= 1e6 { return String(format: "%.1fM", v / 1e6) }
    if v >= 1e3 { return String(format: "%.1fK", v / 1e3) }
    return String(n)
}

/// 集計済み HTML に埋め込まれた JSON から、日別の数字を取り出す
func loadDaily() -> [DayStat]? {
    guard let s = try? String(contentsOf: htmlURL, encoding: .utf8),
          let a = s.range(of: "/*DATA*/"),
          let b = s.range(of: "/*END*/", range: a.upperBound..<s.endIndex) else { return nil }
    let json = String(s[a.upperBound..<b.lowerBound])
    guard json != "null",
          let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let daily = obj["daily"] as? [[String: Any]] else { return nil }
    return daily.compactMap { d in
        guard let day = d["d"] as? String, let t = d["t"] as? Int else { return nil }
        return DayStat(day: day, tokens: t, responses: d["r"] as? Int ?? 0)
    }
}

/// 今日を含む直近 days 日の合計（days が 0 なら全期間）
func total(_ daily: [DayStat], days: Int) -> (tokens: Int, responses: Int) {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    let now = Date()
    let today = f.string(from: now)
    let cutoff = days > 0 ? f.string(from: now.addingTimeInterval(Double(-(days - 1)) * 86400)) : "0000-00-00"
    var t = 0, r = 0
    for d in daily where d.day >= cutoff && d.day <= today {
        t += d.tokens
        r += d.responses
    }
    return (t, r)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var webView: WKWebView?
    var busy = false
    var daily: [DayStat]?
    // メニューバーに表示する期間（日数）。選択は記憶する
    var barDays: Int = {
        let v = UserDefaults.standard.object(forKey: "barDays") as? Int ?? 1
        return periods.contains { $0.days == v } ? v : 1
    }()
    var lastUpdated: Date?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude 使用履歴") {
            img.isTemplate = true
            statusItem.button?.image = img
        }
        daily = loadDaily()
        updateStatusItem()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.refresh() }

        // ログイン時の自動起動ではウィンドウを開かない
        var loginLaunch = false
        if let ev = NSAppleEventManager.shared().currentAppleEvent,
           let prop = ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)),
           prop.enumCodeValue == AEKeyword(keyAELaunchedAsLogInItem) { loginLaunch = true }
        if !loginLaunch { showWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: ステータス表示

    func updateStatusItem() {
        if let d = daily {
            statusItem.button?.title = " " + tok(total(d, days: barDays).tokens)
        } else {
            statusItem.button?.title = ""
        }
        let menu = NSMenu()
        func label(_ s: String) {
            let item = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let d = daily {
            for p in periods {
                let s = total(d, days: p.days)
                label("\(p.name): \(tok(s.tokens)) トークン（応答 \(s.responses) 件）")
            }
        } else {
            label("集計データがありません")
        }
        if let t = lastUpdated {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            label("最終更新: \(f.string(from: t))")
        }
        menu.addItem(.separator())

        // メニューバーに表示する期間
        let barItem = NSMenuItem(title: "メニューバーに表示する期間", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for p in periods {
            let item = NSMenuItem(title: p.name, action: #selector(selectPeriod(_:)), keyEquivalent: "")
            item.target = self
            item.tag = p.days
            item.state = p.days == barDays ? .on : .off
            sub.addItem(item)
        }
        barItem.submenu = sub
        menu.addItem(barItem)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "ダッシュボードを開く", action: #selector(openDashboard), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let reload = NSMenuItem(title: busy ? "集計中…" : "今すぐ更新", action: #selector(refresh), keyEquivalent: "r")
        reload.target = self
        reload.isEnabled = !busy
        menu.addItem(reload)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func selectPeriod(_ sender: NSMenuItem) {
        barDays = sender.tag
        UserDefaults.standard.set(barDays, forKey: "barDays")
        updateStatusItem()
    }

    // MARK: 集計

    @objc func refresh() {
        if busy { return }
        busy = true
        updateStatusItem()
        DispatchQueue.global().async {
            let (ok, message) = self.runBuild()
            DispatchQueue.main.async {
                self.busy = false
                if ok {
                    self.daily = loadDaily()
                    self.lastUpdated = Date()
                    self.reloadWebView()
                } else {
                    NSLog("build failed: %@", message)
                }
                self.updateStatusItem()
            }
        }
    }

    func runBuild() -> (Bool, String) {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments = [dashboardURL.appendingPathComponent("build_usage.py").path]
        p.currentDirectoryURL = dashboardURL
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write("== \(Date())\n".data(using: .utf8)!)
            p.standardOutput = h
            p.standardError = h
        }
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return (false, "Python を起動できませんでした: \(pythonPath)")
        }
        return (p.terminationStatus == 0, "build_usage.py が終了コード \(p.terminationStatus) で終了しました")
    }

    // MARK: ウィンドウ

    @objc func openDashboard() { showWindow() }

    func showWindow() {
        if window == nil {
            let wv = WKWebView(frame: .zero)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Claude 使用履歴"
            w.contentView = wv
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("MainWindow")
            if !w.setFrameUsingName("MainWindow") { w.center() }
            window = w
            webView = wv
        }
        reloadWebView()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reloadWebView() {
        guard let wv = webView, FileManager.default.fileExists(atPath: htmlURL.path) else { return }
        wv.loadFileURL(htmlURL, allowingReadAccessTo: dashboardURL)
    }

    // MARK: ログイン時起動

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "ログイン時の起動を変更できませんでした"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateStatusItem()
    }

    // ウィンドウ内で使うショートカット（⌘R, ⌘W, ⌘Q）用のメインメニュー
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "表示"); viewItem.submenu = viewMenu
        let reload = NSMenuItem(title: "最新のデータに更新", action: #selector(refresh), keyEquivalent: "r")
        reload.target = self
        viewMenu.addItem(reload)
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "ウインドウ"); winItem.submenu = winMenu
        winMenu.addItem(withTitle: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
