// InfraPack desktop app (macOS): the console in its own window.
//
// A native window with an embedded web view pointed at the local console, so
// the console behaves like an app: its own icon, its own window, no browser
// tabs. Links to tech UIs open in the default browser. Built locally by
// `infrapack app install` with the system swiftc.
import Cocoa
import WebKit

final class InfraPackApp: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var retries = 0
    private var pendingPage: String?           // from an infrapack://<page> URL received before the console loaded

    private var home: String {
        ProcessInfo.processInfo.environment["INFRAPACK_HOME"] ?? (NSHomeDirectory() + "/.infrapack")
    }
    private var consoleURL: URL {
        var port = "1717"
        if let env = try? String(contentsOfFile: home + "/.env", encoding: .utf8) {
            for line in env.split(separator: "\n") where line.hasPrefix("CONSOLE_PORT=") {
                port = String(line.dropFirst("CONSOLE_PORT=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
        }
        return URL(string: port == "80" ? "http://localhost" : "http://localhost:\(port)")!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "InfraPack"
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = webView
        window.setFrameAutosaveName("InfraPackConsole")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        load()
    }

    // infrapack://catalog, infrapack://docker … (from the menu bar app, the CLI, or a link)
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "infrapack" }) else { return }
        let page = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        show(page: page)
    }
    private func show(page: String) {
        let allowed = ["services", "catalog", "settings", "logs", "docker"]
        guard allowed.contains(page) else { return }
        if webView.url?.host == consoleURL.host, webView.url?.port == consoleURL.port {
            webView.evaluateJavaScript("location.hash = '#\(page)'; if (typeof setView === 'function') setView('\(page)');", completionHandler: nil)
        } else {
            pendingPage = page
            load()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let page = pendingPage { pendingPage = nil; show(page: page) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    // -------------------------------------------------------------- load --
    private func load() { webView.load(URLRequest(url: consoleURL, timeoutInterval: 4)) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // console not up yet: start InfraPack and retry a few times with a holding page
        if retries == 0 {
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-lc", "infrapack up >/dev/null 2>&1 || ~/.local/bin/infrapack up >/dev/null 2>&1 || /opt/homebrew/bin/infrapack up >/dev/null 2>&1"]
            try? task.run()
        }
        retries += 1
        let html = """
        <html><body style="font:15px -apple-system,sans-serif;color:#67708a;background:#f5f6fa;display:flex;height:100vh;
        align-items:center;justify-content:center;margin:0"><div style="text-align:center">
        <div style="font-size:18px;color:#151a28;font-weight:600;margin-bottom:6px">Starting InfraPack…</div>
        \(retries > 12 ? "The console is not answering. Is Docker running? Try <code>infrapack doctor</code> in a terminal." : "The console comes up in a few seconds.")
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        if retries <= 12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.load() }
        }
    }

    // ------------------------------------------- browser-ish behaviours --
    // target=_blank links (tech UIs, docs) go to the default browser
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
    // anything that is not the console itself also goes to the browser
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
           url.host != consoleURL.host || url.port != consoleURL.port {
            NSWorkspace.shared.open(url)          // a tech UI, docs, anything not the console
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    // the console uses confirm() / alert()
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "InfraPack"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "InfraPack"
        alert.informativeText = message
        alert.runModal()
        completionHandler()
    }

    // -------------------------------------------------------------- menu --
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About InfraPack", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide InfraPack", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit InfraPack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        let reload = NSMenuItem(title: "Reload", action: #selector(reload), keyEquivalent: "r"); reload.target = self; view.addItem(reload)
        let browser = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowser), keyEquivalent: "b"); browser.target = self; view.addItem(browser)
        viewItem.submenu = view

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = win
        NSApp.mainMenu = main
    }
    @objc private func reload() { retries = 0; load() }
    @objc private func openInBrowser() { NSWorkspace.shared.open(consoleURL) }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = InfraPackApp()
app.delegate = delegate
app.run()
