// InfraPack menu bar app (macOS).
//
// A status-bar item listing the installed techs with on/off toggles and
// "Open" entries for their web UIs. It talks to the console's API on
// localhost, so it shows exactly what the console shows.
//
// Built locally by `infrapack menubar install` with the system swiftc, so no
// unsigned binary is ever downloaded.
import Cocoa
import Foundation

final class InfraPackMenu: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var state: [String: Any] = [:]
    private var reachable = false
    private var busy = Set<String>()

    // ---------------------------------------------------------- console --
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
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let path = Bundle.main.path(forResource: "InfraPack", ofType: "icns"), let icon = NSImage(contentsOfFile: path) {
            icon.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "IP"
        }
        statusItem.button?.toolTip = "InfraPack"
        menu.delegate = self
        statusItem.menu = menu
        refresh()
        Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    // ------------------------------------------------------------- data --
    private func refresh() {
        var req = URLRequest(url: consoleURL.appendingPathComponent("api/state"))
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self else { return }
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                self.reachable = parsed != nil
                if let p = parsed { self.state = p }
                self.updateBadge()
            }
        }.resume()
    }

    private func post(_ path: String, _ body: [String: Any], then: @escaping () -> Void = {}) {
        var req = URLRequest(url: consoleURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 600
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { then(); self.refresh() }
        }.resume()
    }

    private var stacks: [[String: Any]] { state["stacks"] as? [[String: Any]] ?? [] }
    private var services: [[String: Any]] { state["services"] as? [[String: Any]] ?? [] }
    private func services(of stack: String) -> [[String: Any]] { services.filter { ($0["stack"] as? String) == stack } }

    private func updateBadge() {
        let up = services.filter { ($0["up"] as? Bool) == true }.count
        statusItem.button?.toolTip = reachable ? "InfraPack — \(up) service\(up == 1 ? "" : "s") running" : "InfraPack — console not running"
        statusItem.button?.alphaValue = reachable ? 1.0 : 0.45
    }

    // ------------------------------------------------------------- menu --
    private func rebuild() {
        menu.removeAllItems()
        let title = NSMenuItem(title: reachable ? "InfraPack" : "InfraPack — console not running", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if !reachable {
            menu.addItem(item("Start InfraPack", #selector(startInfraPack)))
            menu.addItem(.separator())
            menu.addItem(item("Quit", #selector(quit), key: "q"))
            return
        }
        menu.addItem(item("Open console", #selector(openConsole), key: "o"))
        menu.addItem(.separator())

        if stacks.isEmpty {
            let none = NSMenuItem(title: "Nothing installed — open the console to pick a tech", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for stack in stacks {
            guard let name = stack["name"] as? String else { continue }
            let label = stack["label"] as? String ?? name
            let svcs = services(of: name)
            let up = svcs.filter { ($0["up"] as? Bool) == true }.count
            let starting = svcs.contains { ($0["health"] as? String) == "starting" }
            let toggle = NSMenuItem(title: label, action: #selector(toggleStack(_:)), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = name
            toggle.state = up == 0 ? .off : (up == svcs.count ? .on : .mixed)
            if busy.contains(name) { toggle.title = "\(label) — working…"; toggle.isEnabled = false }
            else if starting { toggle.title = "\(label) — starting" }
            menu.addItem(toggle)
            for svc in svcs where (svc["up"] as? Bool) == true {
                if let link = svc["link"] as? String, let url = URL(string: link) {
                    let open = NSMenuItem(title: "Open \(svc["name"] as? String ?? "UI")", action: #selector(openLink(_:)), keyEquivalent: "")
                    open.target = self
                    open.representedObject = url
                    open.indentationLevel = 1
                    menu.addItem(open)
                }
            }
        }
        if !stacks.isEmpty {
            menu.addItem(.separator())
            menu.addItem(item("Start all", #selector(startAll)))
            menu.addItem(item("Stop all", #selector(stopAll)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    // ---------------------------------------------------------- actions --
    @objc private func openConsole() { NSWorkspace.shared.open(consoleURL) }
    @objc private func openLink(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) } }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleStack(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let up = services(of: name).contains { ($0["up"] as? Bool) == true }
        busy.insert(name)
        post("api/action", ["action": up ? "down" : "up", "stacks": [name]]) { self.busy.remove(name) }
    }
    @objc private func startAll() { act("up") }
    @objc private func stopAll() { act("down") }
    private func act(_ action: String) {
        let names = stacks.compactMap { $0["name"] as? String }
        names.forEach { busy.insert($0) }
        post("api/action", ["action": action, "stacks": names]) { names.forEach { self.busy.remove($0) } }
    }

    @objc private func startInfraPack() {
        // the console is down: run `infrapack up` through a login shell so PATH is the user's
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-lc", "infrapack up >/dev/null 2>&1 || ~/.local/bin/infrapack up >/dev/null 2>&1 || /opt/homebrew/bin/infrapack up >/dev/null 2>&1"]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.refresh() }
    }
}

let app = NSApplication.shared
let delegate = InfraPackMenu()
app.delegate = delegate
app.run()
