import Cocoa
import WebKit

// Claude 使用履歴ダッシュボード（ネイティブアプリ）
// 起動時に build_usage.py で集計し、専用ウィンドウ（WKWebView）で表示する。⌘R で再集計。

let info = Bundle.main.infoDictionary ?? [:]
let dashboardDir = info["DashboardDir"] as? String ?? ""
let pythonPath = info["PythonPath"] as? String ?? "/usr/bin/python3"
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/claude-usage-dashboard.log")

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Claude 使用履歴"
        window.contentView = webView
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    @objc func refresh() {
        if busy { return }
        busy = true
        window.title = "Claude 使用履歴 — 集計中…"
        DispatchQueue.global().async {
            let (ok, message) = self.runBuild()
            DispatchQueue.main.async {
                self.busy = false
                self.window.title = "Claude 使用履歴"
                if ok {
                    let html = URL(fileURLWithPath: dashboardDir).appendingPathComponent("claude-usage-dashboard.html")
                    self.webView.loadFileURL(html, allowingReadAccessTo: URL(fileURLWithPath: dashboardDir))
                } else {
                    let alert = NSAlert()
                    alert.messageText = "集計に失敗しました"
                    alert.informativeText = "\(message)\n\nログ: ~/Library/Logs/claude-usage-dashboard.log"
                    alert.runModal()
                }
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
        p.arguments = [URL(fileURLWithPath: dashboardDir).appendingPathComponent("build_usage.py").path]
        p.currentDirectoryURL = URL(fileURLWithPath: dashboardDir)
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

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Claude 使用履歴を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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
app.setActivationPolicy(.regular)
app.run()
